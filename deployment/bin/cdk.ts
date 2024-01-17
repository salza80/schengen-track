#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { RailsLambdaStack } from '../lib/rails-lambda-stack';

const app = new cdk.App();

// const railsMasterKey = app.node.tryGetContext('railsMasterKey') as string | undefined;
// if (railsMasterKey == undefined) {
//   throw new Error('railsMasterKey not specified in context');
// }

const region = 'eu-central-1';
const account = '360298971790';

 const stagingProps = {
  env: {
    account,
    region
  },
  context: {
    environment: 'staging',
  },
  domain: 'test.schengen-calculator.com',
  sslArn: 'arn:aws:acm:us-east-1:360298971790:certificate/6ab0b755-a5e3-4d2d-ab3b-5eb729ccbfcd',
  paramPath: `/scheng/stage/`
 }

 const productonProps = {
  env: {
    account,
    region
  },
  context: {
    environment: 'production',
  },
  domain: 'schengen-calculator.com',
  sslArn: 'arn:aws:acm:us-east-1:360298971790:certificate/6ab0b755-a5e3-4d2d-ab3b-5eb729ccbfcd',
  paramPath: `/scheng/prod/`
 }

 new RailsLambdaStack(app, 'RailsLambdaStack', stagingProps);
 new RailsLambdaStack(app, 'SchengTrackProd', productonProps);


// new RailsLambdaStack(app, 'RailsLambdaStack', {

//   /* If you don't specify 'env', this stack will be environment-agnostic.
//    * Account/Region-dependent features and context lookups will not work,
//    * but a single synthesized template can be deployed anywhere. */

//   /* Uncomment the next line to specialize this stack for the AWS Account
//    * and Region that are implied by the current CLI configuration. */
//   // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

//   /* Uncomment the next line if you know exactly what Account and Region you
//    * want to deploy the stack to. */
//   // env: { account: '123456789012', region: 'us-east-1' },

//   /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
//     
// });