import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigwv2_integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as certificate from 'aws-cdk-lib/aws-certificatemanager';

import { Platform } from 'aws-cdk-lib/aws-ecr-assets';

import * as path from 'path';
import { SmsSubscription } from 'aws-cdk-lib/aws-sns-subscriptions';
import { Stack } from 'aws-cdk-lib';

export interface HttpApiConstructProps {

}
/**
 * CDK construct to create API Gateway HTTP API with Lambda proxy integration 2.0
 */
export class HttpApiConstruct extends Construct {
  /**
   * Create API Gateway HTTP API with Lambda proxy integration 2.0
   */
  constructor(scope: Construct, id: string, props: HttpApiConstructProps) {
    super(scope, id);

    // Rails HTTP API container image with AWS Lambda Ruby Runtime Interface Client
    const apiContainerImage = lambda.DockerImageCode.fromImageAsset(path.join(__dirname, '../../src'), {
      //platform: Platform.LINUX_ARM64,
      platform: Platform.LINUX_AMD64,
      ignoreMode: cdk.IgnoreMode.DOCKER,

      entrypoint: [
        '/usr/local/bundle/bin/aws_lambda_ric',
      //  '/usr/local/bin/aws_lambda_ric',
       // '/bin/aws_lambda_ric',

      ],
      cmd: [
        'lambda_http.handler',
      ],
    });

    const paramPath = '/scheng/prod/';

    const getParam = (paramName: string) => ssm.StringParameter.valueForStringParameter(
      this, `${paramPath}${paramName}`); 


    // Environment variables for Rails REST API container
    const apiContainerEnvironment = {
      BOOTSNAP_CACHE_DIR: '/tmp/cache',
      RAILS_ENV: 'production',
      RAILS_MASTER_KEY: 'test',
      RAILS_LOG_TO_STDOUT: '1',
      DB_URL: getParam('db_url'),
      SECRET_KEY_BASE: 'test',
      FACEBOOK_ID: getParam('facebook_id'),
      FACEBOOK_SECRET: getParam('facebook_secret'),
      BREVO_LOGIN: getParam('brevo_login'),
      BREVO_PASSWORD: getParam('brevo_password'),
      TASK_PASSWORD: getParam('task_password')
    };

    // Lambda function for Lambda proxy integration of AWS API Gateway HTTP API
    const apiFunction = new lambda.DockerImageFunction(this, 'ApiFunction', {
      //architecture: lambda.Architecture.ARM_64,
      architecture: lambda.Architecture.X86_64,
      memorySize: 2048,

      code: apiContainerImage,
      environment: apiContainerEnvironment,

      timeout: cdk.Duration.minutes(1),
      tracing: lambda.Tracing.ACTIVE,
    });

    // AWS API Gateway HTTP API using Rails as Lambda proxy integration
    const railsHttpApi = new apigwv2.HttpApi(this, 'Api', {
      apiName: 'RailsHttpApi',
      defaultIntegration: new apigwv2_integ.HttpLambdaIntegration('RailsHttpApiProxy', apiFunction, {
        payloadFormatVersion: apigwv2.PayloadFormatVersion.VERSION_2_0,
        parameterMapping: new apigwv2.ParameterMapping().overwriteHeader("host", apigwv2.MappingValue.custom("test.schengen-calculator.com"))
      }),
    });

    const customDomain = 'test.schengen-calculator.com';
    const sslCertificateArn = 'arn:aws:acm:us-east-1:360298971790:certificate/6ab0b755-a5e3-4d2d-ab3b-5eb729ccbfcd';
    const origin = new origins.HttpOrigin(`${railsHttpApi.apiId}.execute-api.${Stack.of(this).region}.amazonaws.com`);
    const customOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "customDefaultRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.allowList('Origin', 'Access-Control-Request-Method', 'Access-Control-Request-Headers'),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.allowList('_schengen_track_session'),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    })

    const customCacheCountryGuestKey = new cloudfront.CachePolicy(this, "cacheCountryGuestKey", {
      headerBehavior: cloudfront.CacheHeaderBehavior.allowList('Origin'),
      cookieBehavior: cloudfront.CacheCookieBehavior.allowList('cache_country_guest'),
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.all(),
      enableAcceptEncodingBrotli: true,
      enableAcceptEncodingGzip: true
    })

    const customNoBrowserHeaderResponsePolicy = new cloudfront.ResponseHeadersPolicy(this, "noBrowserCache", {
      removeHeaders: ['_schengen_track_session'],
      customHeadersBehavior: {
        customHeaders: [{
          header: 'Cache-Control',
          value: 'no-cache, no-store, must-revalidate',
          override: true
        }]
      }
    });

    const cloudfrontDist = new cloudfront.Distribution(this, 'schengen-calculator', {
      certificate: certificate.Certificate.fromCertificateArn(this, "sslCertificate", sslCertificateArn),
      domainNames: [customDomain],
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
      sslSupportMethod: cloudfront.SSLMethod.SNI,
      defaultBehavior: {
        origin: origin,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: customOriginRequestPolicy
      },
      additionalBehaviors: {
        "assets/*": {
          origin: origin,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        },
        "/": {
          origin: origin,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: customCacheCountryGuestKey,
          originRequestPolicy: customOriginRequestPolicy,
          responseHeadersPolicy: customNoBrowserHeaderResponsePolicy
        },
        "/about*": {
          origin: origin,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: customCacheCountryGuestKey,
          originRequestPolicy: customOriginRequestPolicy,
          responseHeadersPolicy: customNoBrowserHeaderResponsePolicy
        }
        ,
        "/robots.txt": {
          origin: origin,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: customCacheCountryGuestKey,
          originRequestPolicy: customOriginRequestPolicy,
          responseHeadersPolicy: customNoBrowserHeaderResponsePolicy
        }
      }
    });

    new cdk.CfnOutput(this, 'CloudFrontUrl', {
      value: cloudfrontDist.domainName!,
    });
  }
}