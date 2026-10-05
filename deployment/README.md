# Schengen Calculator CDK

Infrastructure for the Lambda-based Rails app lives in this directory. The stacks are written in TypeScript (AWS CDK v2) and package the Rails code as container-based Lambda functions.

## Pre-requisites

- Node.js 24.18.0 (`.nvmrc` is provided)
- AWS CDK CLI v2.1129.0 (`npm install -g aws-cdk@2.1129.0`)
- Docker (needed to build the Lambda container images)
- Bootstrapped environment: `cdk bootstrap aws://<account>/eu-central-1`

Install dependencies with:

```bash
nvm use
npm ci
```

## Stacks

| Stack | Purpose |
| --- | --- |
| `RailsLambdaStack` | Staging infrastructure (HTTP API, CloudFront distribution, Ops Lambda, SSM outputs). |
| `SchengTrackProd` | Production infrastructure (identical resources targeting production domains). |

Both stacks output the CloudFront distribution domain (`CloudFrontUrl`) and the Ops Lambda name (`OpsLambdaFunctionName`). The GitHub Actions workflows rely on these logical IDs—avoid renaming them without updating the workflows.

## Required Parameter Store Values

The stacks expect environment-scoped SSM parameters under `paramPath` (`/scheng/staging/` or `/scheng/prod/`). Runtime-only secrets should be stored as SecureString parameters:

- `{paramPath}ga_api_secret`
- `{paramPath}schengen_agent_auth_header`

The CloudFront origin header must be an SSM String parameter because CloudFront origin custom headers do not support CloudFormation `ssm-secure` dynamic references:

- `{paramPath}cloudfront_origin_auth_header`

CDK passes the parameter names to Rails/MCP Lambdas and grants `ssm:GetParameter`; it does not put these values in Lambda environment variables.

## Common commands

```bash
# Diff a stack against deployed state
npx cdk diff RailsLambdaStack

# Deploy staging stack
npx cdk deploy RailsLambdaStack --require-approval never

# Deploy production stack
npx cdk deploy SchengTrackProd --require-approval never

# Run tests (Jest)
npm test

# Synthesize CloudFormation template
npx cdk synth RailsLambdaStack
```

## Modifying stacks

Public HTML behaviors exclude query parameters from both the cache key and
origin requests. Keep these policies aligned: forwarding an unkeyed parameter
that changes a response can cache that response for unrelated visitors.
Dynamic and authentication behaviors continue forwarding query parameters.
The shared GitHub Actions test suite runs the CDK template assertions with Jest.

Root, About, blog, and legal pages are session-free and publicly cached for one
hour, separately by locale in the URL. They never create guest users. All pages
share the same header template; only the user menu is loaded separately on public
pages from `/:locale/session_header`. That endpoint is explicitly uncached, reads
only an existing session, and returns the shared user-menu partial and CSRF token.
Keep personalized details, flash messages, and CSRF tokens out of public HTML.
Redirects set a non-sensitive `has_flash_message` hint so the same uncached
endpoint delivers notices once, even after logout or account deletion. Messages
are rendered with the shared notice partial and consumed only by that request.

The JavaScript-readable `has_calculator_session` cookie is only a hint to load
the menu, not authorization. Older sessions are discovered by one probe per tab;
an absent/deleted session returns 204 without creating users or people. Calculator
pages continue rendering the personalized menu directly. Deployments must
invalidate existing CloudFront HTML to remove old person links from the cache
(the deployment workflow already invalidates `/*`).

1. Update the TypeScript sources under `lib/`.
2. Run `npm test` to execute unit tests (if present).
3. Use `npx cdk diff <stack>` to review the impact.
4. Deploy the stack.

Remember that Lambda images are built from `../src`; any Ruby changes require rebuilding and redeploying the stack.
