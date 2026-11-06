export {};
const { filterOriginRequest } = require('../origin-signer/request-profile.cjs');
const request = (profile: string, headers: any = {}) => ({
  headers, origin: { custom: { customHeaders: { 'x-schengen-header-profile': [{ value: profile }] } } },
});
const header = (value: string) => [{ value }];

test('public and calculator profiles discard unkeyed content negotiation and arbitrary cookies', () => {
  for (const profile of ['public', 'calculator']) {
    const input = request(profile, { accept: header('text/csv'),
      cookie: header('unrelated=bad; _schengen_track_session=encrypted=; has_calculator_session=1'),
      'x-schengen-agent-auth': header('forged'), 'x-schengen-client-ip': header('forged'),
      'x-forwarded-for': header('forged'), authorization: header('forged') });
    expect(filterOriginRequest(input)).toBe(true);
    expect(input.headers.accept).toBeUndefined();
    expect(input.headers.authorization).toBeUndefined();
    expect(input.headers['x-schengen-agent-auth']).toBeUndefined();
    expect(input.headers['x-schengen-client-ip']).toBeUndefined();
    expect(input.headers['x-forwarded-for']).toBeUndefined();
    expect(input.headers.cookie).toEqual(profile === 'calculator'
      ? [{ key: 'Cookie', value: '_schengen_track_session=encrypted=; has_calculator_session=1' }] : undefined);
  }
});

test('read-only transport and conditional headers retain exactly their existing values', () => {
  const names = ['accept-encoding', 'cdn-loop', 'content-length', 'if-modified-since',
    'if-none-match', 'if-range', 'if-unmodified-since', 'transfer-encoding', 'via'];
  const original = Object.fromEntries(names.map(name => [name, header('original-'+name)]));
  const input = request('public', { ...original, 'x-unkeyed': header('drop') });
  expect(filterOriginRequest(input)).toBe(true);
  expect(input.headers).toEqual(original);
  for (const name of names) expect(input.headers[name]).toBe(original[name]);
});

test('authentication retains native form, OAuth and CSRF headers and cookies', () => {
  const original = { 'content-type': header('application/x-www-form-urlencoded'),
    origin: header('https://example.com'), referer: header('https://example.com/users/sign_in'),
    accept: header('text/html'), cookie: header('oauth_state=state; csrf=token; _schengen_track_session=encrypted') };
  const input = request('auth', { ...original });
  expect(filterOriginRequest(input)).toBe(true);
  expect(input.headers).toEqual(original);
});

test('private API headers are limited to their own profiles and cannot be selected by viewer input', () => {
  const mcp = request('mcp', { 'mcp-session-id': header('session'), 'mcp-protocol-version': header('version'),
    'content-type': header('application/json'), cookie: header('user=private'),
    'x-schengen-agent-auth': header('agent') });
  expect(filterOriginRequest(mcp)).toBe(true);
  expect(mcp.headers['mcp-session-id']).toBeDefined();
  expect(mcp.headers.cookie).toBeUndefined();
  expect(mcp.headers['x-schengen-agent-auth']).toBeUndefined();
  const agent = request('agent', { 'x-schengen-agent-source': header('mcp'),
    'x-schengen-agent-auth': header('private'), 'x-schengen-agent-client-id': header('client'),
    'content-type': header('application/json'), 'mcp-session-id': header('unrelated') });
  expect(filterOriginRequest(agent)).toBe(true);
  expect(agent.headers['x-schengen-agent-auth']).toBeDefined();
  expect(agent.headers['x-schengen-agent-client-id']).toBeDefined();
  expect(agent.headers['mcp-session-id']).toBeUndefined();
  const input = request('public', { 'x-schengen-header-profile': header('auth'), cookie: header('private=1') });
  expect(filterOriginRequest(input)).toBe(true);
  expect(input.headers).toEqual({});
  expect(filterOriginRequest(request('__proto__'))).toBe(false);
  expect(filterOriginRequest(request('unknown'))).toBe(false);
});
