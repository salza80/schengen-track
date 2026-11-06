# Schengen Calculator CDK

The TypeScript CDK stacks create the Rails HTTP and Ops Lambdas, MCP Lambda,
API Gateways, and CloudFront distribution.

Rails Lambda images exclude the development and test Bundler groups during
gem installation and at runtime.

## Prerequisites

- Node.js (`.nvmrc` is provided)
- Docker (needed to build the Lambda container images)

Run commands in this guide from `deployment/`. Install dependencies with:

```bash
nvm use
npm ci
```

## Stacks

| Stack | Purpose |
| --- | --- |
| `RailsLambdaStack` | Staging at `test.schengen-calculator.com`, with a 30-day anonymous calculator cache. |
| `SchengTrackProd` | Production at `schengen-calculator.com`, with a 30-day anonymous calculator cache. |

The deployment workflows resolve the `OpsLambdaFunctionName` stack output to
run database operations.

## Shared CloudFront cache policies

`SchengTrackProd` owns six custom policies. Staging references their existing
IDs from `lib/production-cache-policy-ids.ts`, which is account configuration
for `360298971790`. It creates no policies of its own. Both environments use
the calculator TTL configured once in `bin/cdk.ts`.

Public HTML and SEO/docs share one policy; their origin forwarding and browser
headers remain independent. The other five policies cover Trips, Calendar,
authenticated/default routes, immutable assets, and named assets.

Deploy staging and production normally, in either order: the referenced policies
already exist. Staging removes its seven local policies; production removes its
redundant SEO/docs policy. After both deployments, Schengen uses six policies
instead of 14. No new policies or spare quota slots are needed.

Keep the six production policies' construct IDs and scope unchanged to preserve
their CloudFormation identities and physical names. Changes to shared settings
affect both environments. If a policy is replaced or this app moves to another
account, update the configured IDs deliberately. Detach staging before removing
its production policies, and account for the quota needed to recreate local
policies when rolling staging back to a pre-sharing revision.

## Parameter Store

The stacks expect environment-scoped SSM parameters under `paramPath`
(`/scheng/staging/` or `/scheng/prod/`). Configure these ordinary parameters:

- `{paramPath}facebook_id` — Facebook App ID.
- `{paramPath}facebook_callback_url` — OAuth callback URL for the environment.
- `{paramPath}brevo_login` — Brevo SMTP username.

Store runtime secrets as `SecureString` parameters. Request traffic uses Neon's
pooled endpoint, while administrative database work uses a direct connection:

- `{paramPath}secrets/db_pooler_url` — pooled URL used by the HTTP API Lambda.
- `{paramPath}secrets/db_direct_url` — direct URL used by the Ops Lambda for migrations,
  country updates, and guest cleanup.

Other boot-time secrets:

- `{paramPath}secrets/rails_master_key`
- `{paramPath}secrets/secret_key_base`
- `{paramPath}secrets/facebook_secret`
- `{paramPath}secrets/brevo_password`

Secrets loaded on demand:

- `{paramPath}secrets/ga_api_secret`
- `{paramPath}secrets/schengen_agent_auth_header`

The retired `{paramPath}cloudfront_origin_auth_header` parameter is no longer
read, forwarded or accepted. Its value provides no access after this version
is deployed to that environment. Remove the obsolete parameter after checking
for other consumers; do not rotate a value still used by an older deployment.

CDK injects the Facebook and Brevo non-secret values directly. For
`SecureString` values it passes only parameter names, grants access to the
required ARNs, and fetches the values at runtime. Boot-time secrets are fetched
together and retained only in the running process.

GitHub Actions authenticates to AWS through OIDC and reads the
`AWS_DEFAULT_REGION` repository variable. The current stacks use
`eu-central-1`. A separate `<stack name>OriginEdge` stack in `us-east-1` owns the
origin signer and its execution role. Bootstrap both regions before the first
deployment. CDK deploys the edge dependency before the application stack.
The edge stack uses `CliCredentialsStackSynthesizer` with the existing staging
bucket and the caller's credentials. It does not assume or pass the region's
administrator-backed CDK deployment/execution roles. The current account's
additional deployer policy is versioned in `iam/origin-edge-deploy.json` and
scopes CloudFormation, Lambda and version-reference parameter writes to the
two Schengen edge stacks. Existing workload-role and asset-bucket permissions
remain prerequisites. Apply it as a separate `SchengenOriginEdgeDeploy` inline
policy on `sst3-template-deploy` when configuring this account. Production
continues to use the existing manual release workflow. Workflows use
CDK's `--method direct` so this policy needs no account-wide change-set access;
CloudFormation still handles updates and rollback.

## Origin authentication

Both HTTP APIs require IAM authorization on their default routes. Every
CloudFront behavior signs origin requests with AWS SigV4 using a dedicated
Lambda@Edge role's temporary credentials. The role can invoke only the two
environment APIs. Rails and MCP accept the viewer IP only when API Gateway's
verified IAM context names that exact role, and reject other callers before
application work or static-file serving. Headers containing the old bearer
and a forged viewer IP do not authenticate a request.

The origin signer derives the viewer IP from CloudFront's read-only `clientIp`
field and signs the method, path, query, complete body and IP header. Requests
whose bodies exceed Lambda@Edge's 1 MiB inspection limit receive 413. Normal
forms and OAuth retain their original bodies, URLs and cookies; clients do not
perform signing. Cached hits avoid the origin signer. This adds Lambda@Edge
invocations for cache misses and private requests.

Origin policies forward all viewer headers except `Host` so generated SigV4
headers survive forwarding. Each behavior selects a trusted header/cookie
profile through origin configuration. Before signing, the function strips
viewer headers and cookies outside that profile and preserves CloudFront's
read-only transport headers. Public and calculator read profiles exclude `Accept`
so unkeyed content negotiation cannot populate their HTML cache with another
format; both discard session cookies on GET/HEAD. Calculator mutations retain
the required session cookies, content type and CSRF headers. Authentication retains
native form, OAuth and CSRF headers and cookies. Viewer headers cannot select
a profile. Cache keys and query forwarding remain defined by the original
CloudFront policies. The signature authenticates CloudFront to the origin;
application sessions control private content.

Calculator GET/HEAD cache misses (including private, localized and format variants)
share a 120-request UTC-minute quota per native viewer IPv4 address or IPv6
/64. The existing origin signer checks this quota before invoking Rails;
cookies, query values and viewer identity headers cannot select another
bucket. Private session responses remain `no-store`, and the six shared cache
policies retain their existing keys and identities.

Each environment owns a regional DynamoDB on-demand table. A conditional
increment enforces the quota across edge replicas; time-window keys reset it
without depending on TTL deletion. Stored keys contain SHA-256 network hashes,
counts and expiry times, rather than raw IP addresses or cookies. TTL cleanup
is asynchronous. The signer can only update items in its environment's table.
Exceeded quotas return uncached 429 with `Retry-After`; unavailable or timed-out
storage returns uncached 503. Requests have a 1.5-second storage deadline and
no automatic SDK retries. Cached hits avoid both the signer and the counter.
Shared networks use one allowance, including signed-in users.

This adds DynamoDB request/storage charges and network time on calculator
cache misses. The table uses pay-per-request billing with maximum read/write
throughput configured at 100 request units per second; throttling fails
closed. This is a throughput control, not an exact monetary spending cap.

`npm run build` bundles the locked AWS signing SDK into the edge asset before
synthesis. The deployment workflow verifies that both direct API endpoints
return 403 for unsigned requests with forged identity headers, then runs the
existing readiness and CloudFront smoke checks. Staging and production remain
separate deployments; merging a PR deploys staging only. The first cutover
updates API authorization, application enforcement and CloudFront in one stack
update; uncached requests can temporarily receive 403 while it propagates.
After invalidation, the workflow waits up to five minutes per public/private
probe for successful signed origin requests before running the full smoke
suite. Persistent failures still fail the release. Validate staging before
scheduling that production change.

Published edge versions are retained because CloudFront may keep replicas
after disassociation. Remove obsolete versions only after AWS has removed
their replicas; they must not block stack updates while still associated.

## CDK commands

```bash
# Diff a stack against deployed state
npx cdk diff RailsLambdaStack

# Compile and test
npm run build
npm test -- --runInBand

# Synthesize CloudFormation template
npx cdk synth RailsLambdaStack
```

## Deployment workflows

Two GitHub Actions workflows deploy the application:

- `Deploy-Staging` deploys `RailsLambdaStack` for same-repository pull requests
  and pushes to `master`. Runs are serialized so smoke tests inspect the version
  deployed by their workflow.
- `Deploy-Prod` manually deploys `SchengTrackProd`.

Each deployment builds and deploys the CDK stack, resolves its
`OpsLambdaFunctionName` output, and invokes the private Ops Lambda to run database
migrations, update country data and verify the shared rate-limit store with a
bounded counter write. Missing or unavailable limiter storage fails the
deployment before cache refresh. Requests during deployment also fail closed
with HTTP 503 if the limiter cannot enforce its quota. Guest cleanup runs through its separate
scheduled or manually dispatched workflow.

After the application and database operations succeed, the workflow updates the
deployment timestamp in Parameter Store, invalidates `/*` in CloudFront, waits
for completion, runs deployed smoke tests, and pre-warms the configured URLs.
Any failed smoke test or cache warm-up fails the workflow.
Smoke tests fetch linked page assets and the Font Awesome fonts referenced by
compiled CSS, checking that fonts are nonempty and have the expected MIME type.

Warm-up target files contain only the environment hostname. The generator expands
shared public routes across all catalogue locales and adds eligible nationality
pages, language sitemaps, and public documents. It uses four concurrent requests.
The deploy workflow generates fresh catalogues in its checkout before warm-up;
the Lambda image build also generates its own copy. For local previews, run
`bundle exec rails country_catalog:generate` from `src/` first.
Production uses the `full` profile; staging uses `sample`, warming only the
American nationality page per language alongside every core public page and
document. Preview staging with
`node scripts/recache_urls.cjs scripts/urls-staging.txt sample`, or production
with `node scripts/recache_urls.cjs scripts/urls-prod.txt full`.

## Cache invariants

Authentication behaviors use a separate viewer function that overwrites the
client-IP header from the viewer connection while preserving host, locale, path
and OAuth query parameters. Keep domain/locale redirects out of these behaviors.

- Root, About, blog, legal, and SEO-document pages are session-free and publicly
  cached for 30 days by localized URL.
- Anonymous Trips and Calendar pages are cached for up to 30 days in staging
  and production, with a seven-day stale fallback. The yearless Calendar entry
  expires, including its stale window, before the next year begins. Their viewer
  function strips all cookies before cache lookup, and the origin signer strips
  them again before public reads reach Rails. Calendar entries vary only by
  normalized `year`. Keep the six shared cache-policy IDs and configurations:
  their legacy cookie allowlists receive no cookie values on these public reads.
  This avoids changing production's shared policies during a staging release.
- `/my/*` and `/*/my/*` have explicitly disabled caching. Signed calculator
  context is validated before calculation; an invalid or absent session redirects
  to the public page without doing calculator work. The read quota covers these
  private URLs too. Public header continuation uses the allowlisted
  `calculator_page` parameter on its uncached endpoint, preserving flash for
  the private destination. Viewer cookie hints never authorize that continuation.
- Fingerprinted assets are cached immutably for one year. Fixed-name icons use
  a seven-day edge and browser cache so they can change without renaming.
- On public pages, personalized menus, notices, and CSRF tokens come from
  uncached endpoints. Never put user data or CSRF tokens in cached HTML.
- Localized country catalogues are generated from the country XML and locale
  files during the Lambda image build, so public country selectors do not query
  the database.
- Forms on cached pages fetch a CSRF token immediately before their first
  submission.
- Keep origin forwarding aligned with cache keys: never forward an unkeyed
  value that can change a cached response.
- Legacy `guest_calculation` links on Trips or Calendar return a non-cacheable
  HTTP redirect to the private confirmation route before the cache is read.
  Keep this as a viewer redirect: a URI rewrite leaves the token in the browser
  URL and retains the original cache behavior. These redirects suppress
  referrers, and ordinary pages send only an origin to cross-origin recipients.
- Deployments invalidate `/*`, run smoke tests, and then warm configured URLs.
