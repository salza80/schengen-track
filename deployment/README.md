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
