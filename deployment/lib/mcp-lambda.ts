import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigwv2_integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Platform } from 'aws-cdk-lib/aws-ecr-assets';
import * as path from 'path';

export interface McpLambdaConstructProps {
  domain: string;
  googleAnalyticsApiSecretParamName: string;
  googleAnalyticsApiSecretParamArn: string;
}

export class McpLambdaConstruct extends Construct {
  public readonly httpApi: apigwv2.HttpApi;
  public readonly function: lambda.DockerImageFunction;

  constructor(scope: Construct, id: string, props: McpLambdaConstructProps) {
    super(scope, id);

    const imageAssetPath = path.join(__dirname, '../..');

    this.function = new lambda.DockerImageFunction(this, 'Function', {
      architecture: lambda.Architecture.X86_64,
      memorySize: 512,
      code: lambda.DockerImageCode.fromImageAsset(imageAssetPath, {
        file: 'mcp-server/Dockerfile',
        ignoreMode: cdk.IgnoreMode.DOCKER,
        exclude: [
          '**',
          '!mcp-server',
          '!mcp-server/**',
          '!src',
          '!src/db',
          '!src/db/data',
          '!src/db/data/countries.xml',
        ],
        platform: Platform.LINUX_AMD64,
      }),
      environment: {
        SCHENGEN_API_BASE_URL: `https://${props.domain}`,
        SCHENGEN_MCP_UPSTREAM_TIMEOUT_SECONDS: '10',
        GA_MEASUREMENT_ID: 'G-E9CCZDHLJF',
        GA_API_SECRET_PARAM: props.googleAnalyticsApiSecretParamName,
      },
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
    });

    this.function.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['ssm:GetParameter'],
      resources: [props.googleAnalyticsApiSecretParamArn],
    }));

    this.httpApi = new apigwv2.HttpApi(this, 'HttpApi', {
      apiName: 'SchengenCalculatorMcpApi',
      defaultIntegration: new apigwv2_integ.HttpLambdaIntegration('McpLambdaIntegration', this.function, {
        payloadFormatVersion: apigwv2.PayloadFormatVersion.VERSION_2_0,
      }),
    });
  }
}
