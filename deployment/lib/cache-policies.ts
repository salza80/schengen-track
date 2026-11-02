import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import { Construct } from 'constructs';

const CACHE_POLICY_KEYS = [
  'publicHtml',
  'tripsIndex',
  'calendarIndex',
  'authenticatedUser',
  'immutableAssets',
  'namedAsset',
] as const;

export type CachePolicyIds = Readonly<Record<typeof CACHE_POLICY_KEYS[number], string>>;
type SchengenCachePolicies = Record<typeof CACHE_POLICY_KEYS[number], cloudfront.ICachePolicy>;

export function schengenCachePolicies(
  scope: Construct,
  calculatorTtlSeconds: number,
  existingPolicyIds?: CachePolicyIds,
): SchengenCachePolicies {
  if (existingPolicyIds) {
    return Object.fromEntries(CACHE_POLICY_KEYS.map(key => [
      key,
      cloudfront.CachePolicy.fromCachePolicyId(scope, `shared${key}CachePolicy`, existingPolicyIds[key]),
    ])) as SchengenCachePolicies;
  }

  const publicCacheProps = {
    headerBehavior: cloudfront.CacheHeaderBehavior.none(),
    cookieBehavior: cloudfront.CacheCookieBehavior.none(),
    queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
    enableAcceptEncodingBrotli: true,
    enableAcceptEncodingGzip: true,
    minTtl: cdk.Duration.seconds(0),
  };
  const calculatorCacheProps = {
    ...publicCacheProps,
    cookieBehavior: cloudfront.CacheCookieBehavior.allowList('_schengen_track_session', 'has_calculator_session'),
    defaultTtl: cdk.Duration.seconds(calculatorTtlSeconds),
    // Preserve the fresh window plus the full seven-day stale fallback.
    maxTtl: cdk.Duration.seconds(calculatorTtlSeconds + cdk.Duration.days(7).toSeconds()),
  };

  // Keep the original construct IDs and scope: these are existing production
  // resources, and moving or renaming them would consume new quota slots.
  return {
    publicHtml: new cloudfront.CachePolicy(scope, 'publicHtmlCachePolicy', {
      ...publicCacheProps,
      // Public HTML and SEO/docs use the same path-only cache key and TTLs.
      defaultTtl: cdk.Duration.days(30),
      maxTtl: cdk.Duration.days(30),
    }),
    tripsIndex: new cloudfront.CachePolicy(scope, 'tripsIndexCachePolicy', calculatorCacheProps),
    calendarIndex: new cloudfront.CachePolicy(scope, 'calendarIndexCachePolicy', {
      ...calculatorCacheProps,
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.allowList('year'),
    }),
    authenticatedUser: new cloudfront.CachePolicy(scope, 'authenticatedUserCache', {
      ...publicCacheProps,
      headerBehavior: cloudfront.CacheHeaderBehavior.allowList('Origin'),
      cookieBehavior: cloudfront.CacheCookieBehavior.allowList('_schengen_track_session'),
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.all(),
      // Preserve compression and the existing 0/0/1 TTL configuration.
      defaultTtl: cdk.Duration.seconds(0),
      maxTtl: cdk.Duration.seconds(1),
    }),
    immutableAssets: new cloudfront.CachePolicy(scope, 'immutableAssetsCachePolicy', {
      ...publicCacheProps,
      defaultTtl: cdk.Duration.days(365),
      maxTtl: cdk.Duration.days(365),
    }),
    namedAsset: new cloudfront.CachePolicy(scope, 'namedAssetCachePolicy', {
      ...publicCacheProps,
      defaultTtl: cdk.Duration.days(7),
      maxTtl: cdk.Duration.days(7),
    }),
  };
}
