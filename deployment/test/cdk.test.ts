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
    expect(cacheConfig(b).ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(originConfig(b).CookiesConfig.CookieBehavior).toBe('none');
    expect(cacheConfig(b).ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.CookieBehavior).toBe('none');
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

test('dynamic and authentication requests still forward query parameters', () => {
  for (const b of [config.DefaultCacheBehavior, behavior('/users/*'), behavior('/api/v1/calculations*')]) {
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('all');
  }

  expect(originConfig(config.DefaultCacheBehavior).CookiesConfig.Cookies).toContain('has_calculator_session');
});

test('legal pages and API docs share a session-free cache', () => {
  for (const path of ['/disclaimer*', '/*/disclaimer*', '/privacy*', '/*/privacy*', '/datadeletion*', '/*/datadeletion*', '/api/docs']) {
    const b = behavior(path);
    const policy = cacheConfig(b);
    expect(b.OriginRequestPolicyId).toBeUndefined();
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.CookiesConfig.CookieBehavior).toBe('none');
    expect(policy.ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(policy.MinTTL).toBe(0);
  }
});
