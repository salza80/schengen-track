// Keep these unchanged: CloudFront rejects removal of origin read-only headers.
const readOnly = ['accept-encoding', 'cdn-loop', 'content-length', 'if-modified-since',
  'if-none-match', 'if-range', 'if-unmodified-since', 'transfer-encoding', 'via'];
const sessionCookies = ['_schengen_track_session', 'has_calculator_session'];
const browserHeaders = ['origin', 'access-control-request-method', 'access-control-request-headers',
  'content-type', 'x-requested-with', 'referer'];
const profiles = {
  public: { headers: [], cookies: [] },
  private: { headers: [...browserHeaders, 'accept'], cookies: sessionCookies },
  calculator: { headers: browserHeaders, cookies: sessionCookies },
  session: { headers: [], cookies: [...sessionCookies, 'has_flash_message'] },
  auth: { headers: [...browserHeaders, 'accept'], cookies: 'all' },
  agent: { headers: ['origin', 'access-control-request-method', 'access-control-request-headers',
    'content-type', 'x-schengen-agent-source', 'x-schengen-agent-auth', 'x-schengen-agent-client-id'], cookies: [] },
  mcp: { headers: ['accept', 'content-type', 'mcp-protocol-version', 'mcp-session-id'], cookies: [] },
};

exports.filterOriginRequest = (request) => {
  const name = request.origin?.custom?.customHeaders?.['x-schengen-header-profile']?.[0]?.value;
  if (!Object.hasOwn(profiles, name)) return false;
  const profile = profiles[name];
  const publicCalculator = name === 'calculator' && ['GET', 'HEAD'].includes(request.method);
  const allowed = new Set([...readOnly, ...(publicCalculator ? [] : profile.headers)]);
  for (const header of Object.keys(request.headers)) {
    if (header !== 'cookie' && !allowed.has(header)) delete request.headers[header];
  }
  const cookieNames = publicCalculator ? [] : profile.cookies;
  if (request.headers.cookie && cookieNames !== 'all') {
    const cookies = request.headers.cookie.flatMap(header => header.value.split(';'))
      .map(cookie => cookie.trim()).filter(cookie => cookieNames.includes(cookie.split('=', 1)[0]));
    if (cookies.length) request.headers.cookie = [{ key: 'Cookie', value: cookies.join('; ') }];
    else delete request.headers.cookie;
  }
  return true;
};
