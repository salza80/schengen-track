# Schengen Calculator CDK

The TypeScript CDK stacks create the Rails HTTP and Ops Lambdas, MCP Lambda,
API Gateways, and CloudFront distribution.

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

`SchengTrackProd` owns six custom cache policies, and `RailsLambdaStack` imports
their IDs through the versioned `SchengenCachePolicies-v1-*` CloudFormation
exports. Public HTML and SEO/docs share one policy; their origin forwarding and
browser response headers remain independent. The other five policies cover
Trips, Calendar, authenticated/default routes, immutable assets, and named assets.
The calculator TTL is also exported so the staging Lambda uses the same fresh
window as the shared policies.

The six production policies keep their existing logical IDs, physical names,
and settings. The rollout creates no cache policies and needs no spare quota.
Staging CI first reads the CloudFormation exports in `eu-central-1`. Before
production publishes the exports, staging keeps its six existing policies and
removes only the redundant SEO/docs policy. Once all seven exports (six IDs and
the calculator TTL) exist, the next staging deployment imports them and removes
its local policies. Failed lookups and incomplete exports stop deployment;
they must not trigger a fallback to creating local policies.

For the **first rollout**, let the PR deploy staging with local policies, merge,
run the normal production deployment, then rerun the staging deployment.
Schengen goes from 14 policies to 13 after the first staging deployment, 12
after production, and six once staging imports the shared policies. Production
can also deploy first; staging will then go straight to shared policies.
AWS-managed policies and the other projects' policies are unaffected.

For manual CDK commands before production has published exports, explicitly
select the staging migration mode:

```bash
npx cdk diff RailsLambdaStack --exclusively --context stagingCachePolicies=local
npx cdk deploy RailsLambdaStack --exclusively --context stagingCachePolicies=local
npx cdk diff SchengTrackProd --exclusively
npx cdk deploy SchengTrackProd --exclusively
npx cdk diff RailsLambdaStack --exclusively
npx cdk deploy RailsLambdaStack --exclusively
```

Use the normal production deployment process for its migrations, invalidation,
smoke tests, and warm-up as well. The initial production diff should remove only
`HttpseoDocsCacheAECA73F5` among cache-policy resources; it must not add or replace
any of the six surviving policies. Initial staging in local mode should remove
only its SEO/docs policy; switching staging to shared mode removes its remaining
six local policies. Neither stage should create any cache policies. The default
CDK staging mode is `shared`; `stagingCachePolicies=local` is for the initial
migration before exports exist, not routine deployments after migration.

After that first rollout, staging and production deploy independently. Explicit
imports deliberately avoid a CDK dependency that could deploy production while
deploying staging. CloudFormation prevents deleting the exported production
policies while staging uses them. Shared policy changes affect both
distributions, so treat `v1` as a stable contract: introduce new versioned
policies and migrate consumers deliberately for future behavior changes.
Before rolling production back to a pre-sharing revision, roll staging back
first and verify it no longer imports these exports.

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

The CloudFront origin header must be an SSM `String` because CloudFront origin
custom headers do not support `ssm-secure` dynamic references. Use a
high-entropy value:

- `{paramPath}cloudfront_origin_auth_header`

CDK injects the Facebook and Brevo non-secret values directly. For
`SecureString` values it passes only parameter names, grants access to the
required ARNs, and fetches the values at runtime. Boot-time secrets are fetched
together and retained only in the running process.

GitHub Actions authenticates to AWS through OIDC and reads the
`AWS_DEFAULT_REGION` repository variable. The current stacks use
`eu-central-1`; bootstrap the target account before its first deployment.

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
migrations and update country data. Guest cleanup runs through its separate
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

- Root, About, blog, legal, and SEO-document pages are session-free and publicly
  cached for 30 days by localized URL.
- Anonymous Trips and Calendar pages are cached for up to 30 days in staging
  and production, with a seven-day stale fallback. The yearless Calendar entry
  expires, including its stale window, before the next year begins. Requests
  with a Rails session or calculator-session hint bypass the anonymous cache.
  Calendar entries vary only by normalized `year`.
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
- Deployments invalidate `/*`, run smoke tests, and then warm configured URLs.
