export {};
const mockSend = jest.fn();
jest.mock('@aws-sdk/client-dynamodb', () => ({
  ...jest.requireActual('@aws-sdk/client-dynamodb'),
  DynamoDBClient: jest.fn(() => ({ send: mockSend })),
}));
const { handler } = require('../origin-signer/index.cjs');

const event = (changes: any = {}) => ({ Records: [{ cf: { request: {
  clientIp: '203.0.113.8', method: 'GET', uri: '/en/visits', querystring: '',
  origin: { custom: { domainName: 'abc123.execute-api.eu-central-1.amazonaws.com', path: '',
    customHeaders: { 'x-schengen-read-quota-table': [{ value: 'trusted-environment-table' }] } } },
  headers: { cookie: [{ value: '_schengen_track_session=invalid; has_calculator_session=arbitrary' }],
    'x-schengen-client-ip': [{ value: '198.51.100.1' }] },
  ...changes,
} } }] });

beforeEach(() => {
  jest.useFakeTimers().setSystemTime(new Date('2026-11-06T12:00:00Z'));
  process.env.AWS_ACCESS_KEY_ID = 'example-key';
  process.env.AWS_SECRET_ACCESS_KEY = 'example-secret';
  process.env.AWS_SESSION_TOKEN = 'example-session';
  mockSend.mockReset().mockResolvedValue({});
});
afterEach(() => {
  jest.useRealTimers();
  for (const key of ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN']) delete process.env[key];
});

test('rotating cookies, headers, locales, endpoints and formats share the native network quota', async () => {
  const buckets = new Map<string, number>();
  mockSend.mockImplementation(async (command: any) => {
    const input = command.input;
    const key = input.Key.bucket.S;
    const count = buckets.get(key) || 0;
    // Model DynamoDB's atomic conditional update; the condition is sent on
    // every increment, including simultaneous requests for a new bucket.
    expect(input.ConditionExpression).toBe('attribute_not_exists(request_count) OR request_count < :limit');
    if (count >= Number(input.ExpressionAttributeValues[':limit'].N)) {
      throw Object.assign(new Error('quota'), { name: 'ConditionalCheckFailedException' });
    }
    buckets.set(key, count + 1);
    return {};
  });
  const requests = Array.from({ length: 121 }, (_, i) => handler(event({
    uri: ['/visits', '/ar/days', '/en/visits.csv', '/%64ays',
      '/en//visits/', '/en/unused/../days', '/%65n/%76isits'][i % 7],
    method: i % 2 ? 'HEAD' : 'GET',
    querystring: `year=${2026 + i % 20}`,
    headers: { cookie: [{ value: `_schengen_track_session=forged-${i}` }],
      'x-schengen-client-ip': [{ value: `192.0.2.${i}` }] },
  })));
  const results = await Promise.all(requests);
  expect(results.filter(r => r.headers.authorization)).toHaveLength(120);
  const denied = results.find(r => r.status === '429');
  expect(denied.headers['retry-after'][0].value).toBe('60');
  expect(denied.headers['cache-control'][0].value).toContain('no-store');
  expect(buckets.size).toBe(1);
  expect([...buckets.values()]).toEqual([120]);
  expect(mockSend.mock.calls[0][0].input.TableName).toBe('trusted-environment-table');
  expect(JSON.stringify(mockSend.mock.calls)).not.toContain('203.0.113.8');

  jest.setSystemTime(new Date('2026-11-06T12:01:00Z'));
  expect((await handler(event())).headers.authorization).toBeDefined();
  expect(buckets.size).toBe(2); // Does not depend on asynchronous TTL deletion.
});

test('IPv6 spelling and hosts in a /64 share a quota, and mapped IPv4 cannot create another bucket', async () => {
  for (const clientIp of ['2001:db8:1:2::1', '2001:0db8:0001:0002:ffff::abcd',
    '2001:db8:1:3::1', '203.0.113.8', '::ffff:203.0.113.8', '203.0.113.9']) {
    await handler(event({ clientIp }));
  }
  const keys = mockSend.mock.calls.map(([command]: any) => command.input.Key.bucket.S);
  expect(keys[0]).toBe(keys[1]);
  expect(keys[0]).not.toBe(keys[2]);
  expect(keys[3]).toBe(keys[4]);
  expect(keys[3]).not.toBe(keys[5]);
});

test('store failures and missing trusted configuration fail closed, while unrelated traffic skips the counter', async () => {
  mockSend.mockRejectedValue(new Error('store unavailable'));
  const unavailable = await handler(event());
  expect(unavailable.status).toBe('503');
  expect(unavailable.headers.authorization).toBeUndefined();
  expect(unavailable.headers['retry-after'][0].value).toBe('60');
  expect(mockSend.mock.calls[0][1].abortSignal).toBeInstanceOf(AbortSignal);
  mockSend.mockClear();
  const missing: any = event();
  missing.Records[0].cf.request.origin.custom.customHeaders = {};
  missing.Records[0].cf.request.headers['x-schengen-read-quota-table'] = [{ value: 'viewer-forged' }];
  expect((await handler(missing)).status).toBe('503');
  for (const changes of [{ uri: '/assets/core.js' }, { uri: '/mcp' }, { uri: '/en/users/sign_in' },
    { method: 'POST' }, { uri: '/' }]) {
    expect((await handler(event(changes))).headers.authorization).toBeDefined();
  }
  expect(mockSend).not.toHaveBeenCalled();
});

test('an unresponsive quota store is aborted before the edge function deadline', async () => {
  jest.useRealTimers();
  mockSend.mockImplementation((_command: any, { abortSignal }: any) => new Promise((_resolve, reject) => {
    abortSignal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  }));
  const started = Date.now();
  expect((await handler(event())).status).toBe('503');
  expect(Date.now() - started).toBeLessThan(4000);
});
