import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as path from 'path';

export class OriginSigner extends Construct {
  readonly roleArn: string;
  readonly association: cloudfront.EdgeLambda;
  readonly invokePolicy: iam.Policy;

  constructor(scope: Construct, id: string, apiArns: string[]) {
    super(scope, id);
    const parent = cdk.Stack.of(this);
    const stackId = `${parent.stackName}OriginEdge`;
    const edgeStack = new cdk.Stack(cdk.Stage.of(this)!, stackId, {
      env: { account: parent.account, region: 'us-east-1' },
      // Use the scoped deployer directly rather than assuming the region's
      // administrator-backed bootstrap deployment/execution roles.
      synthesizer: new cdk.CliCredentialsStackSynthesizer(),
    });
    const roleName = `${parent.stackName}-OriginSigner`;
    const role = new iam.Role(edgeStack, 'SignerRole', {
      roleName,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('edgelambda.amazonaws.com')),
      managedPolicies: [iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')],
    });
    const signer = new cloudfront.experimental.EdgeFunction(this, 'Function', {
      stackId, role, runtime: lambda.Runtime.NODEJS_24_X, handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../origin-signer/dist')),
      memorySize: 128, timeout: cdk.Duration.seconds(5),
    });
    this.roleArn = `arn:${parent.partition}:iam::${parent.account}:role/${roleName}`;
    // Attach the API-specific policy in the regional stack to avoid a circular
    // dependency: the edge stack must exist before its version can be associated.
    this.invokePolicy = new iam.Policy(this, 'InvokePolicy', {
      roles: [iam.Role.fromRoleName(this, 'PolicyRole', roleName)],
      statements: [new iam.PolicyStatement({ actions: ['execute-api:Invoke'], resources: apiArns })],
    });
    this.association = {
      functionVersion: signer.currentVersion,
      eventType: cloudfront.LambdaEdgeEventType.ORIGIN_REQUEST,
      includeBody: true,
    };
  }
}
