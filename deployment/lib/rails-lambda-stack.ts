import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';

//import { RestApiConstruct } from './rest-api';
import { HttpApiConstruct } from './http-api';

export interface RailsLambdaStackProps extends cdk.StackProps {
}

export class RailsLambdaStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RailsLambdaStackProps) {
    super(scope, id, props);

    // new RestApiConstruct(this, 'Rest', {
    //   railsMasterKey: props.railsMasterKey,
    // });

    new HttpApiConstruct(this, 'Http', {});
  }
}