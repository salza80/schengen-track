import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { RailsLambdaStack } from '../lib/rails-lambda-stack';

const stack = new RailsLambdaStack(new cdk.App(), 'CacheTest', {
  env: { account: '123456789012', region: 'eu-central-1' },
  domain: 'example.com',
  altDomain: 'www.example.com',
  sslArn: 'arn:aws:acm:us-east-1:123456789012:certificate/test',
  paramPath: '/test/'
});
const resources = Template.fromStack(stack).toJSON().Resources;
const distribution = Object.values(resources).find((r: any) =>
  r.Type === 'AWS::CloudFront::Distribution') as any;
const config = distribution.Properties.DistributionConfig;
const behavior = (path: string) => config.CacheBehaviors.find((b: any) => b.PathPattern === path);
const cacheConfig = (b: any) => resources[b.CachePolicyId.Ref].Properties.CachePolicyConfig;
const originConfig = (b: any) => resources[b.OriginRequestPolicyId.Ref].Properties.OriginRequestPolicyConfig;
const responseConfig = (b: any) => resources[b.ResponseHeadersPolicyId.Ref].Properties.ResponseHeadersPolicyConfig;
const viewerRequestHandler = () => {
  const functionResource = Object.values(resources).find((r: any) => r.Type === 'AWS::CloudFront::Function') as any;
  return new Function(`${functionResource.Properties.FunctionCode}; return handler;`)();
};
const viewerRequest = (uri: string, querystring: any = {}, host = 'example.com') => ({
  request: { method: 'GET', uri, querystring, headers: { host: { value: host } } },
  viewer: { ip: '192.0.2.1' }
});

test('all origin paths require IAM signatures from the dedicated edge role', () => {
  const edgeStack = stack.node.root.node.findChild('CacheTestOriginEdge') as cdk.Stack;
  expect(edgeStack.synthesizer).toBeInstanceOf(cdk.CliCredentialsStackSynthesizer);
  expect(edgeStack.synthesizer.cloudFormationExecutionRole).toBeUndefined();
  const versions = Object.values(Template.fromStack(edgeStack).toJSON().Resources)
    .filter((r: any) => r.Type === 'AWS::Lambda::Version') as any[];
  expect(versions.length).toBeGreaterThan(0);
  for (const version of versions) {
    expect(version.DeletionPolicy).toBe('Retain');
    expect(version.UpdateReplacePolicy).toBe('Retain');
  }
  const routes = Object.values(resources).filter((r: any) => r.Type === 'AWS::ApiGatewayV2::Route') as any[];
  expect(routes).toHaveLength(2);
  for (const route of routes) expect(route.Properties.AuthorizationType).toBe('AWS_IAM');
  for (const b of [config.DefaultCacheBehavior, ...config.CacheBehaviors]) {
    expect(b.LambdaFunctionAssociations).toHaveLength(1);
    expect(b.LambdaFunctionAssociations[0]).toEqual(expect.objectContaining({ EventType: 'origin-request', IncludeBody: true }));
    // CloudFront otherwise removes Authorization from GET/HEAD origin requests.
    const headers = originConfig(b).HeadersConfig;
    expect(headers.HeaderBehavior).toBe('whitelist');
    expect(headers.Headers).toEqual(expect.arrayContaining([
      'Authorization', 'X-Amz-Date', 'X-Amz-Security-Token', 'X-Amz-Content-Sha256', 'X-Schengen-Client-Ip',
    ]));
    expect(headers.Headers.length).toBeLessThanOrEqual(10);
  }
  for (const origin of config.Origins) {
    expect((origin.OriginCustomHeaders || []).map((h: any) => h.HeaderName))
      .not.toContain('X-Schengen-Origin-Auth');
  }
  const httpFunctions = Object.entries(resources).filter(([id]) =>
    id.includes('HttpApiFunction') || id.includes('HttpMcpFunction')).map(([, r]: any) => r)
    .filter((r: any) => r.Type === 'AWS::Lambda::Function');
  expect(httpFunctions).toHaveLength(2);
  for (const fn of httpFunctions) {
    expect(fn.Properties.Environment.Variables.CLOUDFRONT_ORIGIN_AUTH_PARAM).toBeUndefined();
    expect(JSON.stringify(fn.Properties.Environment.Variables.CLOUDFRONT_SIGNER_ROLE_ARN)).toContain(':role/CacheTest-OriginSigner');
  }
  const policy: any = Object.values(resources).find((r: any) => r.Type === 'AWS::IAM::Policy' &&
    r.Properties.PolicyDocument.Statement.some((s: any) => s.Action === 'execute-api:Invoke'));
  expect(policy.Properties.PolicyDocument.Statement).toHaveLength(2);
  expect(policy.Properties.PolicyDocument.Statement[0].Resource).toHaveLength(2);
  expect(JSON.stringify(policy.Properties.PolicyDocument.Statement)).not.toContain('cloudfront_origin_auth_header');
});

test('calculator origin reads use one environment-specific on-demand quota before Rails', () => {
  const tables = Object.entries(resources).filter(([, r]: any) => r.Type === 'AWS::DynamoDB::Table') as any[];
  expect(tables).toHaveLength(1);
  const [tableId, table] = tables[0];
  expect(table.Properties).toEqual(expect.objectContaining({
    BillingMode: 'PAY_PER_REQUEST',
    KeySchema: [{ AttributeName: 'bucket', KeyType: 'HASH' }],
    TimeToLiveSpecification: { AttributeName: 'expires_at', Enabled: true },
    OnDemandThroughput: { MaxReadRequestUnits: 100, MaxWriteRequestUnits: 100 },
  }));
  const origin = config.Origins.find((o: any) => o.OriginCustomHeaders);
  expect(origin.OriginCustomHeaders).toEqual([
    { HeaderName: 'x-schengen-read-quota-table', HeaderValue: { Ref: tableId } },
  ]);
  const writes = Object.values(resources).filter((r: any) => r.Type === 'AWS::IAM::Policy')
    .flatMap((r: any) => r.Properties.PolicyDocument.Statement)
    .filter((s: any) => s.Action === 'dynamodb:UpdateItem');
  expect(writes).toEqual([expect.objectContaining({
    Resource: { 'Fn::GetAtt': [tableId, 'Arn'] },
  })]);
  expect(Object.values(resources).some((r: any) => r.Type.startsWith('AWS::WAF'))).toBe(false);
});

test('HTTP Lambda uses the pooled database URL while Ops keeps the direct URL', () => {
  const functions = Object.entries(resources).filter(([, resource]: [string, any]) =>
    resource.Type === 'AWS::Lambda::Function') as [string, any][];
  const apiFunction = functions.find(([logicalId]) => logicalId.includes('HttpApiFunction'))?.[1];
  const opsFunction = functions.find(([logicalId]) => logicalId.includes('HttpOpsFunction'))?.[1];

  expect(apiFunction).toBeDefined();
  expect(opsFunction).toBeDefined();
  expect(apiFunction.Properties.Environment.Variables.DB_URL).toBeUndefined();
  expect(opsFunction.Properties.Environment.Variables.DB_URL).toBeUndefined();
  expect(apiFunction.Properties.Environment.Variables.DB_URL_PARAM).toBe('/test/secrets/db_pooler_url');
  expect(opsFunction.Properties.Environment.Variables.DB_URL_PARAM).toBe('/test/secrets/db_direct_url');
});

test('Rails Lambdas receive runtime secret parameter names instead of secret values', () => {
  const functions = Object.entries(resources).filter(([, resource]: [string, any]) =>
    resource.Type === 'AWS::Lambda::Function') as [string, any][];
  const railsFunctions = functions
    .filter(([logicalId]) => logicalId.includes('HttpApiFunction') || logicalId.includes('HttpOpsFunction'))
    .map(([, resource]) => resource);
  const expectedParameters = {
    RAILS_MASTER_KEY_PARAM: '/test/secrets/rails_master_key',
    SECRET_KEY_BASE_PARAM: '/test/secrets/secret_key_base',
    FACEBOOK_SECRET_PARAM: '/test/secrets/facebook_secret',
    BREVO_PASSWORD_PARAM: '/test/secrets/brevo_password',
  };

  expect(railsFunctions).toHaveLength(2);
  for (const fn of railsFunctions) {
    const environment = fn.Properties.Environment.Variables;
    for (const secretName of ['RAILS_MASTER_KEY', 'SECRET_KEY_BASE', 'FACEBOOK_SECRET', 'BREVO_PASSWORD', 'TASK_PASSWORD', 'TASK_PASSWORD_PARAM']) {
      expect(environment[secretName]).toBeUndefined();
    }
    expect(environment).toEqual(expect.objectContaining(expectedParameters));
  }
});

test('Ops Lambda excludes request-only secrets from its environment and IAM policy', () => {
  const functions = Object.entries(resources).filter(([, resource]: [string, any]) =>
    resource.Type === 'AWS::Lambda::Function') as [string, any][];
  const opsFunction = functions.find(([logicalId]) => logicalId.includes('HttpOpsFunction'))?.[1];
  const environment = opsFunction.Properties.Environment.Variables;

  for (const variableName of [
    'GA_MEASUREMENT_ID',
    'GA_API_SECRET_PARAM',
    'CLOUDFRONT_ORIGIN_AUTH_PARAM',
    'SCHENGEN_AGENT_AUTH_PARAM',
  ]) {
    expect(environment[variableName]).toBeUndefined();
  }

  const policies = Object.entries(resources).filter(([, resource]: [string, any]) =>
    resource.Type === 'AWS::IAM::Policy') as [string, any][];
  const opsPolicy = policies.find(([logicalId]) => logicalId.includes('HttpOpsFunctionServiceRoleDefaultPolicy'))?.[1];
  const statements = opsPolicy.Properties.PolicyDocument.Statement;
  const ssmStatement = statements.find((statement: any) =>
    [statement.Action].flat().includes('ssm:GetParameters'));

  expect([ssmStatement.Action].flat()).toEqual(['ssm:GetParameters']);
  expect(ssmStatement.Resource).toContain('arn:aws:ssm:eu-central-1:123456789012:parameter/test/secrets/db_direct_url');
  expect(ssmStatement.Resource).not.toContain('arn:aws:ssm:eu-central-1:123456789012:parameter/test/secrets/ga_api_secret');
  expect(ssmStatement.Resource).not.toContain('arn:aws:ssm:eu-central-1:123456789012:parameter/test/cloudfront_origin_auth_header');
  expect(ssmStatement.Resource).not.toContain('arn:aws:ssm:eu-central-1:123456789012:parameter/test/secrets/schengen_agent_auth_header');
});

test('Facebook web login workaround is off by default and can be explicitly enabled', () => {
  const railsFunctions = (items: any) => Object.values(items).filter((r: any) =>
    r.Type === 'AWS::Lambda::Function' && r.Properties.Environment?.Variables?.FACEBOOK_ID) as any[];
  expect(railsFunctions(resources)).toHaveLength(2);
  for (const fn of railsFunctions(resources)) {
    expect(fn.Properties.Environment.Variables.FACEBOOK_WEB_LOGIN_WORKAROUND).toBe('false');
  }
  const enabled = new RailsLambdaStack(new cdk.App(), 'FacebookWorkaroundTest', {
    env: { account: '123456789012', region: 'eu-central-1' },
    domain: 'test.example.com',
    altDomain: 'test2.example.com',
    sslArn: 'arn:aws:acm:us-east-1:123456789012:certificate/test',
    paramPath: '/test/',
    facebookWebLoginWorkaround: true
  });
  const enabledFunctions = railsFunctions(Template.fromStack(enabled).toJSON().Resources);
  expect(enabledFunctions).toHaveLength(2);
  for (const fn of enabledFunctions) {
    expect(fn.Properties.Environment.Variables.FACEBOOK_WEB_LOGIN_WORKAROUND).toBe('true');
  }
});

test('public HTML ignores query parameters in both cache keys and origin requests', () => {
  for (const path of ['/', '/en', '/fr', '/ar', '/about*', '/*/about*', '/blog*', '/*/blog*']) {
    const b = behavior(path);
    expect(cacheConfig(b).DefaultTTL).toBe(2592000);
    expect(cacheConfig(b).MaxTTL).toBe(2592000);
    expect(cacheConfig(b).ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(originConfig(b).CookiesConfig.CookieBehavior).toBe('none');
    expect(cacheConfig(b).ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.CookieBehavior).toBe('none');
  }
});

test('public HTML and SEO/docs reuse a cache policy while retaining their browser and forwarding policies', () => {
  expect(Object.values(resources).filter((resource: any) => resource.Type === 'AWS::CloudFront::CachePolicy')).toHaveLength(6);
  for (const path of ['/privacy*', '/api/docs', '/robots.txt', '/sitemap*']) {
    const docs = behavior(path);
    expect(docs.CachePolicyId).toEqual(behavior('/').CachePolicyId);
    expect(docs.OriginRequestPolicyId).toEqual(behavior('/').OriginRequestPolicyId);
    expect(docs.ResponseHeadersPolicyId).not.toEqual(behavior('/').ResponseHeadersPolicyId);
    expect(responseConfig(docs).CustomHeadersConfig.Items).toContainEqual(expect.objectContaining({
      Header: 'Cache-Control',
      Value: 'public, max-age=3600, must-revalidate',
      Override: true
    }));
  }
  expect(responseConfig(behavior('/')).RemoveHeadersConfig.Items).toContainEqual({ Header: 'Set-Cookie' });
  expect(responseConfig(behavior('/')).CustomHeadersConfig.Items).toContainEqual(expect.objectContaining({
    Header: 'Cache-Control',
    Value: 'no-cache, no-store, must-revalidate',
    Override: true
  }));
});

test('fingerprinted and fixed-name assets use safe independent cache policies', () => {
  const fingerprinted = behavior('assets/*');
  const fingerprintedPolicy = cacheConfig(fingerprinted);
  expect(fingerprintedPolicy.MinTTL).toBe(0);
  expect(fingerprintedPolicy.DefaultTTL).toBe(31536000);
  expect(fingerprintedPolicy.MaxTTL).toBe(31536000);
  expect(responseConfig(fingerprinted).CustomHeadersConfig.Items).toContainEqual(expect.objectContaining({
    Header: 'Cache-Control',
    Value: 'public, max-age=31536000, immutable',
    Override: true
  }));

  for (const path of ['/favicon.ico', '/med.png']) {
    const fixedName = behavior(path);
    const fixedNamePolicy = cacheConfig(fixedName);
    expect(fixedNamePolicy.MinTTL).toBe(0);
    expect(fixedNamePolicy.DefaultTTL).toBe(604800);
    expect(fixedNamePolicy.MaxTTL).toBe(604800);
    expect(responseConfig(fixedName).CustomHeadersConfig.Items).toContainEqual(expect.objectContaining({
      Header: 'Cache-Control',
      Value: 'public, max-age=604800, must-revalidate',
      Override: true
    }));
  }
});

test('personalized menus are never edge cached and receive the real session', () => {
  for (const path of ['/session_header', '/*/session_header']) {
    const b = behavior(path);
    expect(b.CachePolicyId).toBe('4135ea2d-6df8-44a3-9df3-4b5a84be39ad');
    expect(originConfig(b).CookiesConfig.Cookies).toContain('_schengen_track_session');
    expect(originConfig(b).CookiesConfig.Cookies).toContain('has_calculator_session');
    expect(originConfig(b).CookiesConfig.Cookies).toContain('has_flash_message');
    expect(b.ResponseHeadersPolicyId).toBeUndefined();
  }
});

test('calculator indexes use exact session-aware cache behaviours', () => {
  const calculatorPaths = ['/visits', '/*/visits', '/days', '/*/days'];
  for (const path of calculatorPaths) {
    const headers = originConfig(behavior(path)).HeadersConfig.Headers.map((header: string) => header.toLowerCase());
    expect(headers).toContain('content-type');
    expect(headers).not.toContain('accept');
  }

  for (const path of calculatorPaths.slice(0, 2)) {
    const b = behavior(path);
    const policy = cacheConfig(b);
    expect(policy.MinTTL).toBe(0);
    expect(policy.DefaultTTL).toBe(2592000);
    expect(policy.MaxTTL).toBe(3196800);
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.CookieBehavior).toBe('whitelist');
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.Cookies).toEqual(
      expect.arrayContaining(['_schengen_track_session', 'has_calculator_session'])
    );
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(b.AllowedMethods).toEqual(expect.arrayContaining(['GET', 'HEAD', 'POST', 'PATCH', 'DELETE']));
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(originConfig(b).CookiesConfig.CookieBehavior).toBe('none');
    expect(responseConfig(b).RemoveHeadersConfig).toBeUndefined();
    expect(responseConfig(b).CustomHeadersConfig.Items).toContainEqual(expect.objectContaining({
      Header: 'Cache-Control',
      Value: 'no-cache, no-store, must-revalidate',
      Override: true
    }));
  }

  for (const path of calculatorPaths.slice(2)) {
    const b = behavior(path);
    const policy = cacheConfig(b);
    expect(policy.MinTTL).toBe(0);
    expect(policy.DefaultTTL).toBe(2592000);
    expect(policy.MaxTTL).toBe(3196800);
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.Cookies).toEqual(
      expect.arrayContaining(['_schengen_track_session', 'has_calculator_session'])
    );
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStringBehavior).toBe('whitelist');
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStrings).toEqual(['year']);
    expect(b.AllowedMethods).toEqual(['GET', 'HEAD']);
    expect(responseConfig(b).RemoveHeadersConfig).toBeUndefined();
    expect(responseConfig(b).CustomHeadersConfig.Items).toContainEqual(expect.objectContaining({
      Header: 'Cache-Control',
      Value: 'no-cache, no-store, must-revalidate',
      Override: true
    }));
  }
});

test('CSRF bootstrap routes are never edge cached', () => {
  for (const path of ['/csrf_token', '/*/csrf_token']) {
    const b = behavior(path);
    expect(b.CachePolicyId).toBe('4135ea2d-6df8-44a3-9df3-4b5a84be39ad');
    expect(originConfig(b).CookiesConfig.Cookies).toContain('_schengen_track_session');
    expect(b.ResponseHeadersPolicyId).toBeUndefined();
  }
});

test('calendar viewer requests normalize and isolate the year query', () => {
  const handler = viewerRequestHandler();
  const currentYear = new Date().getUTCFullYear();

  expect(handler(viewerRequest('/en/days', { month: { value: '4' } })).querystring).toEqual({
    year: { value: String(currentYear) }
  });
  expect(handler(viewerRequest('/days', {
    year: { value: '9999' },
    month: { value: '4' },
    utm_source: { value: 'bot' }
  })).querystring).toEqual({ year: { value: String(currentYear + 20) } });
  expect(handler(viewerRequest('/en/visits', { open: { value: 'trip' } })).querystring).toEqual({
    open: { value: 'trip' }
  });
});

test('guest tokens leave every calculator URL before cached HTML can render', () => {
  const handler = viewerRequestHandler();
  const locales = ['', '/en', '/de', '/es', '/tr', '/zh-CN', '/hi', '/pt-BR', '/ar', '/fr', '/pt'];
  for (const prefix of locales) {
    for (const page of ['visits', 'days']) {
      const b = behavior(prefix ? '/*/' + page : '/' + page);
      expect(b.FunctionAssociations).toEqual(config.DefaultCacheBehavior.FunctionAssociations);
      for (const host of ['example.com', 'www.example.com']) {
        for (const method of ['GET', 'HEAD']) {
          const event = viewerRequest(prefix + '/' + page, {
            guest_calculation: { value: 'signed/token+value' }, year: { value: '2027' }
          }, host);
          event.request.method = method;
          expect(handler(event)).toEqual({
            statusCode: 302,
            statusDescription: 'Found',
            headers: {
              location: { value: 'https://example.com/calculations/signed%2Ftoken%2Bvalue' },
              'cache-control': { value: 'private, no-store' },
              'referrer-policy': { value: 'no-referrer' }
            }
          });
        }
      }
    }
  }
});

test('ambiguous empty and oversized guest tokens never fall through to cached HTML', () => {
  const handler = viewerRequestHandler();
  for (const parameter of [
    { value: '' },
    { value: '', multiValue: [{ value: '' }, { value: 'valid-second-bearer' }] },
    { value: 'first-bearer', multiValue: [{ value: 'first-bearer' }, { value: 'second-bearer' }] },
    { value: 'x'.repeat(2049) }
  ]) {
    for (const uri of ['/en/visits', '/en/days']) {
      const result = handler(viewerRequest(uri, { guest_calculation: parameter }));
      expect(result.statusCode).toBe(302);
      expect(result.headers.location.value).toBe('https://example.com/calculations/invalid-token');
      expect(result.headers['referrer-policy'].value).toBe('no-referrer');
      expect(result.headers['cache-control'].value).toBe('private, no-store');
    }
  }
});

test('viewer requests permanently redirect legacy Portuguese URLs to pt-BR', () => {
  const handler = viewerRequestHandler();

  expect(handler(viewerRequest('/pt'))).toEqual(expect.objectContaining({
    statusCode: 301,
    headers: { location: { value: 'https://example.com/pt-BR' } }
  }));
  expect(handler(viewerRequest('/pt/'))).toEqual(expect.objectContaining({
    statusCode: 301,
    headers: { location: { value: 'https://example.com/pt-BR' } }
  }));
  expect(handler(viewerRequest('/pt/days', {
    year: { value: '2027' },
    month: { value: '4' }
  }))).toEqual(expect.objectContaining({
    statusCode: 301,
    headers: { location: { value: 'https://example.com/pt-BR/days?year=2027&month=4' } }
  }));
  expect(handler(viewerRequest('/pt/about/Brazilian', {}, 'www.example.com'))).toEqual(expect.objectContaining({
    statusCode: 301,
    headers: { location: { value: 'https://example.com/pt-BR/about/Brazilian' } }
  }));
});

test('alternate hostname redirects preserve query parameters', () => {
  const handler = viewerRequestHandler();
  const response = handler(viewerRequest('/about', {
    nationality: { value: 'New Zealander' },
    source: { multiValue: [{ value: 'one' }, { value: 'two' }] }
  }, 'www.example.com'));

  expect(response).toEqual(expect.objectContaining({
    statusCode: 301,
    headers: {
      location: {
        value: 'https://example.com/about?nationality=New%20Zealander&source=one&source=two'
      }
    }
  }));
});

test('calculator fresh TTL override is applied consistently', () => {
  const overridden = new RailsLambdaStack(new cdk.App(), 'ShortCalculatorCacheTest', {
    env: { account: '123456789012', region: 'eu-central-1' },
    domain: 'test.example.com',
    altDomain: 'test2.example.com',
    sslArn: 'arn:aws:acm:us-east-1:123456789012:certificate/test',
    paramPath: '/test/',
    publicCalculatorCacheTtlSeconds: 900
  });
  const overriddenResources = Template.fromStack(overridden).toJSON().Resources;
  const policies = Object.values(overriddenResources)
    .filter((resource: any) => resource.Type === 'AWS::CloudFront::CachePolicy')
    .map((resource: any) => resource.Properties.CachePolicyConfig);
  const calculatorPolicies = policies.filter((policy: any) =>
    policy.ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.Cookies?.includes('has_calculator_session'));
  expect(calculatorPolicies).toHaveLength(2);
  expect(calculatorPolicies.every((policy: any) => policy.DefaultTTL === 900)).toBe(true);
  expect(calculatorPolicies.every((policy: any) => policy.MaxTTL === 605700)).toBe(true);

  const apiFunction = Object.entries(overriddenResources)
    .find(([logicalId, resource]: [string, any]) => logicalId.includes('HttpApiFunction') && resource.Type === 'AWS::Lambda::Function')?.[1] as any;
  expect(apiFunction.Properties.Environment.Variables.PUBLIC_CALCULATOR_CACHE_TTL).toBe('900');
});

test('dynamic and authentication requests still forward query parameters', () => {
  for (const b of [config.DefaultCacheBehavior, behavior('/users/*'), behavior('/api/v1/calculations*')]) {
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('all');
  }

  expect(originConfig(config.DefaultCacheBehavior).CookiesConfig.Cookies).toContain('has_calculator_session');
});

test('authentication routes overwrite viewer identity without rewriting OAuth URLs', () => {
  for (const path of ['/users/*', '/*/users/*']) {
    const auth = behavior(path);
    expect(auth.FunctionAssociations).toHaveLength(1);
    expect(auth.FunctionAssociations).not.toEqual(config.DefaultCacheBehavior.FunctionAssociations);
    expect(originConfig(auth).HeadersConfig.Headers).toContain('X-Schengen-Client-Ip');
    const id = auth.FunctionAssociations[0].FunctionARN['Fn::GetAtt'][0];
    const handler = new Function(`${resources[id].Properties.FunctionCode}; return handler;`)();
    for (const uri of ['/users/auth/facebook/callback', '/ar/users/password', '/pt/users/password']) {
      const event = viewerRequest(uri, { state: { value: 'oauth-state' } }, 'www.example.com');
      event.request.method = 'POST';
      (event.request.headers as any)['x-schengen-client-ip'] = { value: '198.51.100.50' };
      const result = handler(event);
      expect(result.uri).toBe(uri);
      expect(result.method).toBe('POST');
      expect(result.querystring).toEqual({ state: { value: 'oauth-state' } });
      expect(result.headers.host.value).toBe('www.example.com');
      expect(result.headers['x-schengen-client-ip']).toEqual({ value: '192.0.2.1' });
      expect(result.statusCode).toBeUndefined();
    }
  }
});

test('legal pages and API docs share a session-free cache', () => {
  for (const path of ['/disclaimer*', '/*/disclaimer*', '/privacy*', '/*/privacy*', '/datadeletion*', '/*/datadeletion*', '/api/docs', '/robots.txt', '/sitemap*']) {
    const b = behavior(path);
    const policy = cacheConfig(b);
    expect(originConfig(b).HeadersConfig.Headers).toEqual([
      'Authorization', 'X-Amz-Date', 'X-Amz-Security-Token', 'X-Amz-Content-Sha256', 'X-Schengen-Client-Ip',
    ]);
    expect(originConfig(b).CookiesConfig.CookieBehavior).toBe('none');
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.CookieBehavior).toBe('none');
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(policy.MinTTL).toBe(0);
    expect(policy.DefaultTTL).toBe(2592000);
    expect(policy.MaxTTL).toBe(2592000);
  }
});
