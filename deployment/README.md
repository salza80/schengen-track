# Schengen Calculator CDK

Infrastructure for the Lambda-based Rails app lives in this directory. The stacks are written in TypeScript (AWS CDK v2) and package the Rails code as container-based Lambda functions.

## Pre-requisites

- Node.js 20.18.0 (`.nvmrc` is provided)
- AWS CDK CLI v2 (`npm install -g aws-cdk`)
- Docker (needed to build the Lambda container images)
- Bootstrapped environment: `cdk bootstrap aws://<account>/eu-central-1`

Install dependencies with:

```bash
nvm use 20
npm install
```

## Stacks

| Stack | Purpose |
| --- | --- |
| `RailsLambdaStack` | Staging infrastructure (HTTP API, CloudFront distribution, Ops Lambda, SSM outputs). |
| `SchengTrackProd` | Production infrastructure (identical resources targeting production domains). |

Both stacks output the CloudFront distribution domain (`CloudFrontUrl`) and the Ops Lambda name (`OpsLambdaFunctionName`). The GitHub Actions workflows rely on these logical IDs—avoid renaming them without updating the workflows.

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

1. Update the TypeScript sources under `lib/`.
2. Run `npm test` to execute unit tests (if present).
3. Use `npx cdk diff <stack>` to review the impact.
4. Deploy the stack.

Remember that Lambda images are built from `../src`; any Ruby changes require rebuilding and redeploying the stack.
