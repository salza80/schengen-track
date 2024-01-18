import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { HttpApiConstruct } from './http-api';

export interface RailsLambdaStackProps extends cdk.StackProps {
  domain: string,
  sslArn: string,
  paramPath: string
}

export class RailsLambdaStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RailsLambdaStackProps) {
    super(scope, id, props);
    new HttpApiConstruct(this, 'Http', { domain: props.domain, sslArn: props.sslArn, paramPath: props.paramPath});
  }
}