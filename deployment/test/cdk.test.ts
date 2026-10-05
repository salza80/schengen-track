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
  for (const path of ['/', '/en', '/about*', '/*/about*', '/blog*', '/*/blog*']) {
    const b = behavior(path);
    expect(cacheConfig(b).ParametersInCacheKeyAndForwardedToOrigin.QueryStringsConfig.QueryStringBehavior).toBe('none');
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('none');
  }
});

test('dynamic and authentication requests still forward query parameters', () => {
  for (const b of [config.DefaultCacheBehavior, behavior('/users/*'), behavior('/api/v1/calculations*')]) {
    expect(originConfig(b).QueryStringsConfig.QueryStringBehavior).toBe('all');
  }
});
