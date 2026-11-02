import * as fs from 'fs';
import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { RailsLambdaStack } from '../lib/rails-lambda-stack';
import { productionCachePolicyIds } from '../lib/production-cache-policy-ids';

const app = new cdk.App();
const common = {
  env: { account: '360298971790', region: 'eu-central-1' },
  sslArn: 'arn:aws:acm:us-east-1:360298971790:certificate/test',
};
const production = new RailsLambdaStack(app, 'SchengTrackProd', {
  ...common,
  domain: 'schengen-calculator.com',
  altDomain: 'www.schengen-calculator.com',
  paramPath: '/scheng/prod/',
});
const staging = new RailsLambdaStack(app, 'RailsLambdaStack', {
  ...common,
  domain: 'test.schengen-calculator.com',
  altDomain: 'test2.schengen-calculator.com',
  paramPath: '/scheng/staging/',
  cachePolicyIds: productionCachePolicyIds,
});
const owner = Template.fromStack(production).toJSON();
const consumer = Template.fromStack(staging).toJSON();
const distribution = (template: any) => (Object.values(template.Resources).find((resource: any) =>
  resource.Type === 'AWS::CloudFront::Distribution') as any).Properties.DistributionConfig;
const policies = (template: any) => Object.fromEntries(Object.entries(template.Resources)
  .filter(([, resource]: [string, any]) => resource.Type === 'AWS::CloudFront::CachePolicy')
  .map(([id, resource]: [string, any]) => [id, resource.Properties.CachePolicyConfig]));

test('six existing production policies keep their logical IDs, physical names, and full configurations', () => {
  // Captured from the production template before consolidation. Keeping names
  // and logical IDs avoids creating replacement policies at the account quota.
  const originalPolicies = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/production-cache-policies.json'), 'utf8'));
  expect(policies(owner)).toEqual(originalPolicies);
  expect(Object.keys(policies(owner))).toHaveLength(6);
  expect(policies(consumer)).toEqual({});
});

test('every staging behavior uses the corresponding production policy', () => {
  const ownerConfig = distribution(owner);
  const consumerConfig = distribution(consumer);
  const ownerBehavior = (pattern: string) => ownerConfig.CacheBehaviors.find((item: any) => item.PathPattern === pattern);
  const policyRefsById: Record<string, unknown> = {
    [productionCachePolicyIds.publicHtml]: ownerBehavior('/').CachePolicyId,
    [productionCachePolicyIds.tripsIndex]: ownerBehavior('/visits').CachePolicyId,
    [productionCachePolicyIds.calendarIndex]: ownerBehavior('/days').CachePolicyId,
    [productionCachePolicyIds.authenticatedUser]: ownerConfig.DefaultCacheBehavior.CachePolicyId,
    [productionCachePolicyIds.immutableAssets]: ownerBehavior('assets/*').CachePolicyId,
    [productionCachePolicyIds.namedAsset]: ownerBehavior('/favicon.ico').CachePolicyId,
  };
  const ownerBehaviors = [ownerConfig.DefaultCacheBehavior, ...ownerConfig.CacheBehaviors];
  const consumerBehaviors = [consumerConfig.DefaultCacheBehavior, ...consumerConfig.CacheBehaviors];

  expect(consumerBehaviors.map((behavior: any) => behavior.PathPattern)).toEqual(
    ownerBehaviors.map((behavior: any) => behavior.PathPattern));
  const sharedPolicies = new Set<string>();
  for (const [index, behavior] of consumerBehaviors.entries()) {
    const ownerBehavior = ownerBehaviors[index];
    expect(typeof behavior.CachePolicyId).toBe('string');
    if (policyRefsById[behavior.CachePolicyId]) sharedPolicies.add(behavior.CachePolicyId);
    expect(policyRefsById[behavior.CachePolicyId] ?? behavior.CachePolicyId).toEqual(ownerBehavior.CachePolicyId);

    // Sharing a cache policy must not change methods, compression, origin
    // forwarding, or viewer response headers for any route.
    const resolveBehavior = (template: any, item: any) => {
      const { CachePolicyId, TargetOriginId, ...rest } = item;
      rest.TargetOriginIndex = distribution(template).Origins.findIndex((origin: any) => origin.Id === TargetOriginId);
      expect(rest.TargetOriginIndex).toBeGreaterThanOrEqual(0);
      for (const field of ['OriginRequestPolicyId', 'ResponseHeadersPolicyId']) {
        if (rest[field]) {
          const properties = template.Resources[rest[field].Ref].Properties;
          const config = properties.OriginRequestPolicyConfig ?? properties.ResponseHeadersPolicyConfig;
          const { Name, ...settings } = config;
          rest[field] = settings;
        }
      }
      return rest;
    };
    expect(resolveBehavior(consumer, behavior)).toEqual(resolveBehavior(owner, ownerBehavior));
  }
  expect([...sharedPolicies].sort()).toEqual(Object.values(productionCachePolicyIds).sort());
});

test('both environments keep the same calculator fresh TTL', () => {
  for (const template of [owner, consumer]) {
    const httpFunction = Object.entries(template.Resources).find(([id, resource]: [string, any]) =>
      id.includes('HttpApiFunction') && resource.Type === 'AWS::Lambda::Function')?.[1] as any;
    expect(httpFunction.Properties.Environment.Variables.PUBLIC_CALCULATOR_CACHE_TTL).toBe('2592000');
  }
});

test('staging synthesis does not introduce a production deployment dependency', () => {
  const assembly = app.synth();
  const dependencies = assembly.getStackArtifact(staging.artifactId).dependencies.map(artifact => artifact.id);
  expect(dependencies).not.toContain(production.artifactId);
});
