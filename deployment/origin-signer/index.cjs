const { SignatureV4 } = require('@smithy/signature-v4');
const { HttpRequest } = require('@smithy/protocol-http');
const { Sha256 } = require('@aws-crypto/sha256-js');
const { isIP } = require('node:net');
const { checkCalculatorReadLimit } = require('./calculator-read-limit.cjs');
const { filterOriginRequest } = require('./request-profile.cjs');

const failure = (status, message) => ({
  status: String(status),
  headers: { 'cache-control': [{ key: 'Cache-Control', value: 'private, no-store' }] },
  body: message,
});

// CloudFront supplies clientIp and origin; neither comes from viewer headers.
// Sign only stable identity headers, plus the method, URL and complete body.
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  if (request.body?.inputTruncated) return failure(413, 'Request too large');
  const domain = request.origin?.custom?.domainName;
  const match = /^([a-z0-9]+)\.execute-api\.([a-z0-9-]+)\.amazonaws\.com$/.exec(domain || '');
  if (!match || !isIP(request.clientIp)) return failure(503, 'Origin unavailable');
  const { AWS_ACCESS_KEY_ID: accessKeyId, AWS_SECRET_ACCESS_KEY: secretAccessKey,
    AWS_SESSION_TOKEN: sessionToken } = process.env;
  if (!accessKeyId || !secretAccessKey || !sessionToken) return failure(503, 'Origin unavailable');

  try {
    if (!filterOriginRequest(request)) return failure(503, 'Origin unavailable');
    const quota = await checkCalculatorReadLimit(request, match[2]);
    if (quota) {
      const response = failure(quota.status, quota.status === 429
        ? 'Too many calculator requests. Try again shortly.' : 'Calculator temporarily unavailable.');
      response.headers['retry-after'] = [{ key: 'Retry-After', value: String(quota.retryAfter) }];
      return response;
    }
    const query = Object.create(null);
    // URLSearchParams preserves repeated keys and decodes form-style + values.
    for (const [key, value] of new URLSearchParams(request.querystring)) {
      (query[key] ||= []).push(value);
    }
    const body = request.body
      ? Buffer.from(request.body.data, request.body.encoding === 'base64' ? 'base64' : 'utf8')
      : Buffer.alloc(0);
    const signer = new SignatureV4({
      service: 'execute-api', region: match[2], sha256: Sha256,
      credentials: { accessKeyId, secretAccessKey, sessionToken },
    });
    const signed = await signer.sign(new HttpRequest({
      protocol: 'https:', hostname: domain, method: request.method,
      path: `${request.origin.custom.path || ''}${request.uri}`, query, body,
      headers: { host: domain, 'x-schengen-client-ip': request.clientIp },
    }));
    for (const name of ['authorization', 'x-amz-date', 'x-amz-security-token',
      'x-amz-content-sha256', 'x-schengen-origin-auth']) delete request.headers[name];
    for (const [key, value] of Object.entries(signed.headers)) {
      request.headers[key] = [{ key, value }];
    }
    return request;
  } catch {
    // Never log the event, body, signature, session credentials or URLs.
    return failure(503, 'Origin unavailable');
  }
};
