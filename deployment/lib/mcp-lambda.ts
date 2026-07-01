import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigwv2_integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Platform } from 'aws-cdk-lib/aws-ecr-assets';
import * as path from 'path';

export interface McpLambdaConstructProps {
  domain: string;
}

export class McpLambdaConstruct extends Construct {
  public readonly httpApi: apigwv2.HttpApi;
  public readonly function: lambda.DockerImageFunction;

  constructor(scope: Construct, id: string, props: McpLambdaConstructProps) {
    super(scope, id);

    const imageAssetPath = path.join(__dirname, '../../mcp-server');

    this.function = new lambda.DockerImageFunction(this, 'Function', {
      architecture: lambda.Architecture.X86_64,
      memorySize: 512,
      code: lambda.DockerImageCode.fromImageAsset(imageAssetPath, {
        platform: Platform.LINUX_AMD64,
      }),
      environment: {
        SCHENGEN_API_BASE_URL: `https://${props.domain}`,
        SCHENGEN_MCP_UPSTREAM_TIMEOUT_SECONDS: '10',
      },
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
    });

    this.httpApi = new apigwv2.HttpApi(this, 'HttpApi', {
      apiName: 'SchengenCalculatorMcpApi',
      defaultIntegration: new apigwv2_integ.HttpLambdaIntegration('McpLambdaIntegration', this.function, {
        payloadFormatVersion: apigwv2.PayloadFormatVersion.VERSION_2_0,
      }),
    });
  }
}
