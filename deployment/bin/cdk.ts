#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { RailsLambdaStack } from '../lib/rails-lambda-stack';
import { productionCachePolicyIds } from '../lib/production-cache-policy-ids';

const app = new cdk.App();
const region = 'eu-central-1';
const account = '360298971790';
const publicCalculatorCacheTtlSeconds = 30 * 24 * 60 * 60;

 const stagingProps = {
  env: {
    account,
    region
  },
  context: {
    environment: 'staging',
  },
  domain: 'test.schengen-calculator.com',
  facebookWebLoginWorkaround: true,
  altDomain: 'test2.schengen-calculator.com',
  sslArn: 'arn:aws:acm:us-east-1:360298971790:certificate/6ab0b755-a5e3-4d2d-ab3b-5eb729ccbfcd',
  paramPath: `/scheng/staging/`,
  publicCalculatorCacheTtlSeconds,
  cachePolicyIds: productionCachePolicyIds
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
  facebookWebLoginWorkaround: true,
  altDomain: 'www.schengen-calculator.com',
  sslArn: 'arn:aws:acm:us-east-1:360298971790:certificate/6ab0b755-a5e3-4d2d-ab3b-5eb729ccbfcd',
  paramPath: `/scheng/prod/`,
  publicCalculatorCacheTtlSeconds
 }

 new RailsLambdaStack(app, 'RailsLambdaStack', stagingProps);
 new RailsLambdaStack(app, 'SchengTrackProd', productonProps);
