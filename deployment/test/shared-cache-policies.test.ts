import * as fs from 'fs';
import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { RailsLambdaStack, RailsLambdaStackProps } from '../lib/rails-lambda-stack';
import { stagingCachePolicyProps } from '../lib/cache-policies';

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
  sharedCachePolicyRole: 'owner',
});
const staging = new RailsLambdaStack(app, 'RailsLambdaStack', {
  ...common,
  domain: 'test.schengen-calculator.com',
  altDomain: 'test2.schengen-calculator.com',
  paramPath: '/scheng/staging/',
  sharedCachePolicyRole: 'consumer',
});
const owner = Template.fromStack(production).toJSON();
const consumer = Template.fromStack(staging).toJSON();
const localStaging = new RailsLambdaStack(new cdk.App(), 'RailsLambdaStack', {
  ...common,
  domain: 'test.schengen-calculator.com',
  altDomain: 'test2.schengen-calculator.com',
  paramPath: '/scheng/staging/',
  ...stagingCachePolicyProps('local', 2592000),
});
const local = Template.fromStack(localStaging).toJSON();
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

test('initial staging keeps the same six policy resources and transitions without changing route behavior', () => {
  expect(Object.keys(policies(local)).sort()).toEqual(Object.keys(policies(owner)).sort());
  for (const [id, config] of Object.entries(policies(local))) {
    const { Name: localName, ...localSettings } = config as any;
    const { Name: ownerName, ...ownerSettings } = policies(owner)[id] as any;
    expect(localName).toMatch(/^RailsLambdaStackHttp/);
    expect(localSettings).toEqual(ownerSettings);
  }
  const localConfig = distribution(local);
  const consumerConfig = distribution(consumer);
  const localBehaviors = [localConfig.DefaultCacheBehavior, ...localConfig.CacheBehaviors];
  const consumerBehaviors = [consumerConfig.DefaultCacheBehavior, ...consumerConfig.CacheBehaviors];
  const exports = Object.fromEntries(Object.values(owner.Outputs).map((output: any) => [output.Export?.Name, output.Value]));
  for (const [index, item] of localBehaviors.entries()) {
    const { CachePolicyId: localPolicy, ...localBehavior } = item;
    const { CachePolicyId: consumerPolicy, ...consumerBehavior } = consumerBehaviors[index];
    expect(localBehavior).toEqual(consumerBehavior);
    expect(consumerPolicy['Fn::ImportValue'] ? exports[consumerPolicy['Fn::ImportValue']] : consumerPolicy).toEqual(localPolicy);
  }
});

test('every staging behavior uses the corresponding exported production policy', () => {
  const exports = Object.fromEntries(Object.values(owner.Outputs).map((output: any) => [output.Export?.Name, output.Value]));
  const ownerConfig = distribution(owner);
  const consumerConfig = distribution(consumer);
  const ownerBehaviors = [ownerConfig.DefaultCacheBehavior, ...ownerConfig.CacheBehaviors];
  const consumerBehaviors = [consumerConfig.DefaultCacheBehavior, ...consumerConfig.CacheBehaviors];

  expect(consumerBehaviors.map((behavior: any) => behavior.PathPattern)).toEqual(
    ownerBehaviors.map((behavior: any) => behavior.PathPattern));
  const importedPolicies = new Set<string>();
  for (const [index, behavior] of consumerBehaviors.entries()) {
    const ownerBehavior = ownerBehaviors[index];
    const importedName = behavior.CachePolicyId['Fn::ImportValue'];
    if (importedName) importedPolicies.add(importedName);
    expect(importedName ? exports[importedName] : behavior.CachePolicyId).toEqual(ownerBehavior.CachePolicyId);

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
  expect([...importedPolicies].sort()).toEqual([
    'SchengenCachePolicies-v1-authenticatedUser',
    'SchengenCachePolicies-v1-calendarIndex',
    'SchengenCachePolicies-v1-immutableAssets',
    'SchengenCachePolicies-v1-namedAsset',
    'SchengenCachePolicies-v1-publicHtml',
    'SchengenCachePolicies-v1-tripsIndex',
  ]);
});

test('staging takes its calculator fresh TTL from the owner', () => {
  const ttlExport = Object.values(owner.Outputs).find((output: any) =>
    output.Export?.Name === 'SchengenCachePolicies-v1-calculatorTtlSeconds') as any;
  expect(ttlExport.Value).toBe('2592000');
  const httpFunction = Object.entries(consumer.Resources).find(([id, resource]: [string, any]) =>
    id.includes('HttpApiFunction') && resource.Type === 'AWS::Lambda::Function')?.[1] as any;
  expect(httpFunction.Properties.Environment.Variables.PUBLIC_CALCULATOR_CACHE_TTL).toEqual({
    'Fn::ImportValue': 'SchengenCachePolicies-v1-calculatorTtlSeconds',
  });
});

test('staging synthesis does not introduce a production deployment dependency', () => {
  const assembly = app.synth();
  const dependencies = assembly.getStackArtifact(staging.artifactId).dependencies.map(artifact => artifact.id);
  expect(dependencies).not.toContain(production.artifactId);
});

test('consumers cannot silently override the shared calculator TTL', () => {
  const props: RailsLambdaStackProps = {
    ...common,
    domain: 'test.example.com',
    altDomain: 'test2.example.com',
    paramPath: '/test/',
    sharedCachePolicyRole: 'consumer',
    publicCalculatorCacheTtlSeconds: 900,
  };
  expect(() => new RailsLambdaStack(new cdk.App(), 'InvalidConsumer', props)).toThrow(
    'Shared cache policy consumers must use the calculator TTL exported by the owner');
});
