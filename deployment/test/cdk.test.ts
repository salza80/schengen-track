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
