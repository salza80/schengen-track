import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { HttpApiConstruct } from './http-api';
import { SharedCachePolicyRole } from './cache-policies';

export interface RailsLambdaStackProps extends cdk.StackProps {
  domain: string,
  sslArn: string,
  paramPath: string,
  altDomain: string,
  facebookWebLoginWorkaround?: boolean,
  publicCalculatorCacheTtlSeconds?: number,
  sharedCachePolicyRole?: SharedCachePolicyRole
}

export class RailsLambdaStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RailsLambdaStackProps) {
    super(scope, id, props);
    new HttpApiConstruct(this, 'Http', {
      domain: props.domain,
      altDomain: props.altDomain,
      sslArn: props.sslArn,
      paramPath: props.paramPath,
      facebookWebLoginWorkaround: props.facebookWebLoginWorkaround,
      publicCalculatorCacheTtlSeconds: props.publicCalculatorCacheTtlSeconds,
      sharedCachePolicyRole: props.sharedCachePolicyRole
    });
  }
}
