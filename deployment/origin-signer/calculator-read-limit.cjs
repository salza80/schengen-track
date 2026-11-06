const { DynamoDBClient, UpdateItemCommand } = require('@aws-sdk/client-dynamodb');
const { createHash } = require('node:crypto');
const ipaddr = require('ipaddr.js');

const clients = new Map();
const PERIOD = 60;
const LIMIT = 120;

// Count only origin reads: CloudFront cache hits never invoke this function.
exports.checkCalculatorReadLimit = async (request, region) => {
  if (!['GET', 'HEAD'].includes(request.method)) return null;
  let path;
  try { path = decodeURIComponent(request.uri); } catch { return { status: 503, retryAfter: PERIOD }; }
  // Match the normalized route too, even when the origin sees an encoded or
  // non-canonical URL that missed CloudFront's calculator cache behavior.
  const segments = [];
  for (const segment of path.split('/')) {
    if (!segment || segment === '.') continue;
    if (segment === '..') segments.pop(); else segments.push(segment);
  }
  path = '/' + segments.join('/');
  if (!/^\/(?:[^/]+\/)?(?:visits|days)(?:\.[^/]+)?\/?$/.test(path)) return null;

  // Origin metadata is distribution configuration, not a viewer header.
  const table = request.origin.custom.customHeaders?.['x-schengen-read-quota-table']?.[0]?.value;
  if (!table) return { status: 503, retryAfter: PERIOD };
  try {
    const address = ipaddr.process(request.clientIp);
    const bytes = address.toByteArray();
    const network = address.kind() === 'ipv6' ? bytes.slice(0, 8) : bytes;
    const digest = createHash('sha256').update(Buffer.from(network)).digest('hex');
    const window = Math.floor(Date.now() / 1000 / PERIOD);
    if (!clients.has(region)) clients.set(region, new DynamoDBClient({ region, maxAttempts: 1 }));
    await clients.get(region).send(new UpdateItemCommand({
      TableName: table,
      Key: { bucket: { S: `${window}:${digest}` } },
      UpdateExpression: 'SET expires_at = :expiry ADD request_count :one',
      ConditionExpression: 'attribute_not_exists(request_count) OR request_count < :limit',
      ExpressionAttributeValues: {
        ':expiry': { N: String((window + 2) * PERIOD) },
        ':one': { N: '1' }, ':limit': { N: String(LIMIT) },
      },
    }), { abortSignal: AbortSignal.timeout(1500) });
    return null;
  } catch (error) {
    if (error.name === 'ConditionalCheckFailedException') {
      const remaining = PERIOD - Math.floor(Date.now() / 1000) % PERIOD;
      return { status: 429, retryAfter: remaining };
    }
    // Store failures never authorize unlimited calculator work. No IPs logged.
    return { status: 503, retryAfter: PERIOD };
  }
};
