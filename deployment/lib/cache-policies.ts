import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import { Construct } from 'constructs';

export type SharedCachePolicyRole = 'owner' | 'consumer';
export type StagingCachePolicyMode = 'local' | 'shared';

export function stagingCachePolicyProps(mode: unknown, calculatorTtlSeconds: number): {
  sharedCachePolicyRole?: SharedCachePolicyRole;
  publicCalculatorCacheTtlSeconds?: number;
} {
  if (mode === 'local') return { publicCalculatorCacheTtlSeconds: calculatorTtlSeconds };
  if (mode === 'shared') return { sharedCachePolicyRole: 'consumer' };
  throw new Error('stagingCachePolicies must be local or shared');
}

// Production owns these exports. Consumers use explicit imports so deploying
// staging never implicitly deploys the production application as a dependency.
export const SHARED_CACHE_POLICY_EXPORT_PREFIX = 'SchengenCachePolicies-v1';
export const CACHE_POLICY_KEYS = [
  'publicHtml',
  'tripsIndex',
  'calendarIndex',
  'authenticatedUser',
  'immutableAssets',
  'namedAsset',
] as const;

export type SchengenCachePolicies = Readonly<Record<typeof CACHE_POLICY_KEYS[number], cloudfront.ICachePolicy>> & {
  readonly publicCalculatorCacheTtlSeconds: string;
};

export function schengenCachePolicies(
  scope: Construct,
  role?: SharedCachePolicyRole,
  calculatorTtlSeconds?: number,
): SchengenCachePolicies {
  if (role === 'consumer') {
    if (calculatorTtlSeconds !== undefined) {
      throw new Error('Shared cache policy consumers must use the calculator TTL exported by the owner');
    }

    return {
      ...Object.fromEntries(CACHE_POLICY_KEYS.map(key => [
        key,
        cloudfront.CachePolicy.fromCachePolicyId(
          scope,
          `shared${key}CachePolicy`,
          cdk.Fn.importValue(`${SHARED_CACHE_POLICY_EXPORT_PREFIX}-${key}`),
        ),
      ])) as Record<typeof CACHE_POLICY_KEYS[number], cloudfront.ICachePolicy>,
      publicCalculatorCacheTtlSeconds: cdk.Fn.importValue(`${SHARED_CACHE_POLICY_EXPORT_PREFIX}-calculatorTtlSeconds`),
    };
  }

  const freshTtl = calculatorTtlSeconds ?? cdk.Duration.days(30).toSeconds();
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
    defaultTtl: cdk.Duration.seconds(freshTtl),
    // Preserve the fresh window plus the full seven-day stale fallback.
    maxTtl: cdk.Duration.seconds(freshTtl + cdk.Duration.days(7).toSeconds()),
  };

  // Keep the original construct IDs and scope: these are existing production
  // resources, and moving or renaming them would consume new quota slots.
  const policies: SchengenCachePolicies = {
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
    publicCalculatorCacheTtlSeconds: freshTtl.toString(),
  };

  if (role === 'owner') {
    for (const key of CACHE_POLICY_KEYS) {
      new cdk.CfnOutput(scope, `SharedCachePolicy${key}`, {
        value: policies[key].cachePolicyId,
        exportName: `${SHARED_CACHE_POLICY_EXPORT_PREFIX}-${key}`,
      });
    }
    new cdk.CfnOutput(scope, 'SharedCachePolicyCalculatorTtlSeconds', {
      value: policies.publicCalculatorCacheTtlSeconds,
      exportName: `${SHARED_CACHE_POLICY_EXPORT_PREFIX}-calculatorTtlSeconds`,
    });
  }

  return policies;
}
