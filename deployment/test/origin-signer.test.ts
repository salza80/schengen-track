const { handler } = require('../origin-signer/index.cjs');
import { createHash } from 'crypto';

const event = (changes: any = {}) => ({ Records: [{ cf: { request: {
  clientIp: '203.0.113.8', method: 'POST', uri: '/en/users/password',
  querystring: 'state=a%2Bb&state=x+y&empty=',
  origin: { custom: { domainName: 'abc123.execute-api.eu-central-1.amazonaws.com', path: '' } },
  headers: {
    host: [{ value: 'forged.example' }],
    authorization: [{ value: 'forged' }],
    'x-amz-date': [{ value: 'old' }],
    'x-amz-security-token': [{ value: 'forged' }],
    'x-schengen-origin-auth': [{ value: 'old-bearer' }],
    'x-schengen-client-ip': [{ value: '192.0.2.99' }],
    cookie: [{ value: 'session=test' }],
  },
  body: { data: Buffer.from('user[email]=test%40example.invalid').toString('base64'), encoding: 'base64', inputTruncated: false },
  ...changes,
} } }] });

beforeEach(() => {
  jest.useFakeTimers().setSystemTime(new Date('2026-11-06T12:00:00Z'));
  process.env.AWS_ACCESS_KEY_ID = 'example-key';
  process.env.AWS_SECRET_ACCESS_KEY = 'example-secret';
  process.env.AWS_SESSION_TOKEN = 'example-session';
});
afterEach(() => {
  jest.useRealTimers();
  for (const key of ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN']) delete process.env[key];
});

test('signs the complete native form and authoritative IP while preserving URL, cookies and body', async () => {
  const input = event();
  const original = structuredClone(input.Records[0].cf.request);
  const result = await handler(input);
  expect(result.uri).toBe(original.uri);
  expect(result.querystring).toBe(original.querystring);
  expect(result.body).toEqual(original.body);
  expect(result.headers.cookie).toEqual(original.headers.cookie);
  expect(result.headers['x-schengen-origin-auth']).toBeUndefined();
  expect(result.headers['x-schengen-client-ip'][0].value).toBe('203.0.113.8');
  expect(result.headers.host[0].value).toBe(original.origin.custom.domainName);
  expect(result.headers.authorization[0].value).toContain('/eu-central-1/execute-api/aws4_request');
  expect(result.headers.authorization[0].value).toContain('host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-schengen-client-ip');
  expect(result.headers['x-amz-content-sha256'][0].value).toBe(
    createHash('sha256').update(Buffer.from(original.body.data, 'base64')).digest('hex'));
});

test('method, path, query, body and viewer IP are bound to each request', async () => {
  const signature = async (changes: any) => (await handler(event(changes))).headers.authorization[0].value;
  const original = await signature({});
  for (const change of [{ method: 'DELETE' }, { uri: '/en/users/sign_in' },
    { querystring: 'state=different' }, { clientIp: '203.0.113.9' },
    { body: { data: 'changed', encoding: 'text', inputTruncated: false } }]) {
    expect(await signature(change)).not.toBe(original);
  }
  process.env.AWS_SESSION_TOKEN = 'rotated-session';
  expect(await signature({})).not.toBe(original);
});

test('fails closed on missing credentials, unexpected origin and truncated bodies', async () => {
  expect((await handler(event({ body: { inputTruncated: true } }))).status).toBe('413');
  expect((await handler(event({ origin: { custom: { domainName: 'attacker.example' } } }))).status).toBe('503');
  expect((await handler(event({ clientIp: 'forged' }))).status).toBe('503');
  delete process.env.AWS_SESSION_TOKEN;
  const result = await handler(event());
  expect(result.status).toBe('503');
  expect(result.headers['cache-control'][0].value).toContain('no-store');
});
