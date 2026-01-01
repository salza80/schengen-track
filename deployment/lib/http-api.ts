import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigwv2_integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as certificate from 'aws-cdk-lib/aws-certificatemanager';
import { createRedirectFunction } from './createRedirectFunction';

import { Platform } from 'aws-cdk-lib/aws-ecr-assets';
import * as ecr from 'aws-cdk-lib/aws-ecr';

import * as path from 'path';
// import { SmsSubscription } from 'aws-cdk-lib/aws-sns-subscriptions';
import { Stack } from 'aws-cdk-lib';

export interface HttpApiConstructProps {
  domain: string,
  altDomain: string,
  sslArn: string,
  paramPath: string
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
    const imageAssetPath = path.join(__dirname, '../../src');
    const baseImageProps = {
      //platform: Platform.LINUX_ARM64,
      platform: Platform.LINUX_AMD64,
      ignoreMode: cdk.IgnoreMode.DOCKER,
      entrypoint: [
        '/usr/local/bundle/bin/aws_lambda_ric',
      ],
    };

    const apiContainerImage = lambda.DockerImageCode.fromImageAsset(imageAssetPath, {
      ...baseImageProps,
      cmd: [
        'lambda_http.handler',
      ],
    });

    const opsContainerImage = lambda.DockerImageCode.fromImageAsset(imageAssetPath, {
      ...baseImageProps,
      cmd: [
        'lambda_tasks.handler',
      ],
    });
  
    const customDomain = props.domain;
    const altDomain = props.altDomain;
    const cfRewriteUrlFunction = new cloudfront.Function(this, 'rewriteUrl', {
      code: cloudfront.FunctionCode.fromInline(createRedirectFunction(altDomain, customDomain))
    });

    const getParam = (paramName: string) => ssm.StringParameter.valueForStringParameter(
      this, `${props.paramPath}${paramName}`); 


    // Environment variables for Rails REST API container
    const apiContainerEnvironment = {
      BOOTSNAP_CACHE_DIR: '/tmp/cache',
      RAILS_ENV: 'production',
      RAILS_MASTER_KEY: getParam('rails_master_key'),
      RAILS_LOG_TO_STDOUT: '1',
      DB_URL: getParam('db_url'),
      SECRET_KEY_BASE: getParam('secret_key_base'),
      FACEBOOK_ID: getParam('facebook_id'),
      FACEBOOK_SECRET: getParam('facebook_secret'),
      FACEBOOK_CALLBACK_URL: getParam('facebook_callback_url'),
      BREVO_LOGIN: getParam('brevo_login'),
      BREVO_PASSWORD: getParam('brevo_password'),
      TASK_PASSWORD: getParam('task_password'),
      DOMAIN: customDomain
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

    const opsFunction = new lambda.DockerImageFunction(this, 'OpsFunction', {
      architecture: lambda.Architecture.X86_64,
      memorySize: 2048,
      code: opsContainerImage,
      environment: apiContainerEnvironment,
      timeout: cdk.Duration.minutes(15),
      tracing: lambda.Tracing.ACTIVE,
    });

    // Grant Lambda permission to read the deployment timestamp from Parameter Store
    apiFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['ssm:GetParameter'],
      resources: [
        `arn:aws:ssm:${Stack.of(this).region}:${Stack.of(this).account}:parameter/schengen/deployment-timestamp`
      ]
    }));

    // Configure ECR lifecycle policy to clean up old images
    // This will keep the 5 most recent images and delete older ones
    const ecrRepository = ecr.Repository.fromRepositoryName(
      this,
      'CDKAssetsRepository',
      `cdk-hnb659fds-container-assets-${Stack.of(this).account}-${Stack.of(this).region}`
    );

    ecrRepository.addLifecycleRule({
      description: 'Keep only the 5 most recent images',
      maxImageCount: 5,
      rulePriority: 1,
    });

    // AWS API Gateway HTTP API using Rails as Lambda proxy integration
    // overwrite host header with domain, as it will come from cloudfront and rails requires it for security xss checks.
    const railsHttpApi = new apigwv2.HttpApi(this, 'Api', {
      apiName: 'RailsHttpApi',
      defaultIntegration: new apigwv2_integ.HttpLambdaIntegration('RailsHttpApiProxy', apiFunction, {
        payloadFormatVersion: apigwv2.PayloadFormatVersion.VERSION_2_0,
        parameterMapping: new apigwv2.ParameterMapping().overwriteHeader("host", apigwv2.MappingValue.custom(customDomain))
      }),
    });

    const sslCertificateArn = props.sslArn;
    const origin = new origins.HttpOrigin(`${railsHttpApi.apiId}.execute-api.${Stack.of(this).region}.amazonaws.com`);
    const customOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "customDefaultRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.allowList(
        'Origin', 
        'Access-Control-Request-Method', 
        'Access-Control-Request-Headers',
        'Accept',
        'X-Requested-With',
        'Referer'
      ),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.allowList('_schengen_track_session'),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    })

    // Separate policy for authentication flows that need all cookies for CSRF
    const authOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "authRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.allowList(
        'Origin', 
        'Access-Control-Request-Method', 
        'Access-Control-Request-Headers',
        'Accept',
        'X-Requested-With',
        'Referer'
      ),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.all(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    })

    const customCacheCountryGuestKey = new cloudfront.CachePolicy(this, "cacheCountryGuestKey", {
      headerBehavior: cloudfront.CacheHeaderBehavior.allowList('Origin'),
      cookieBehavior: cloudfront.CacheCookieBehavior.allowList('cache_country_guest'),
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.all(),
      enableAcceptEncodingBrotli: true,
      enableAcceptEncodingGzip: true
    })

    // Cache policy for authenticated user pages to enable text compression (Brotli/Gzip) without actual caching
    // This solves Lighthouse "Document request latency" warnings by compressing HTML/CSS/JS responses
    // TTL is set to 0-1 seconds so CloudFront applies compression but doesn't cache dynamic content
    // Respects session cookies to ensure user-specific content is always fresh
    const authenticatedUserCachePolicy = new cloudfront.CachePolicy(this, "authenticatedUserCache", {
      headerBehavior: cloudfront.CacheHeaderBehavior.allowList('Origin'),
      cookieBehavior: cloudfront.CacheCookieBehavior.allowList('_schengen_track_session'),
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.all(),
      enableAcceptEncodingBrotli: true,
      enableAcceptEncodingGzip: true,
      minTtl: cdk.Duration.seconds(0),
      maxTtl: cdk.Duration.seconds(1),
      defaultTtl: cdk.Duration.seconds(0)
    })

    //stop browser caching files that are cached in cloudfront to ensure invalidation works
    const customNoBrowserHeaderResponsePolicy = new cloudfront.ResponseHeadersPolicy(this, "noBrowserCache", {
      removeHeaders: ['Set-Cookie'],
      customHeadersBehavior: {
        customHeaders: [{
          header: 'Cache-Control',
          value: 'no-cache, no-store, must-revalidate',
          override: true
        }]
      }
    });

    // Allow aggressive browser caching for static assets (fingerprinted, so safe to cache long-term)
    const assetsBrowserCachePolicy = new cloudfront.ResponseHeadersPolicy(this, "assetsBrowserCache", {
      customHeadersBehavior: {
        customHeaders: [{
          header: 'Cache-Control',
          value: 'public, max-age=31536000, immutable',
          override: true
        }]
      }
    });

    const functionAssociations = [
      {
        function: cfRewriteUrlFunction,
        eventType: cloudfront.FunctionEventType.VIEWER_REQUEST,
      },
    ];

    const publicCacheByCountryGuestBehavior = {
      origin: origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: customCacheCountryGuestKey,
      originRequestPolicy: customOriginRequestPolicy,
      responseHeadersPolicy: customNoBrowserHeaderResponsePolicy,
      functionAssociations
    };

    const publicAssetsCacheBehavior = {
      origin: origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      responseHeadersPolicy: assetsBrowserCachePolicy,
      functionAssociations
    };

    const authFlowBehavior = {
      origin: origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: authOriginRequestPolicy,
      // Removed functionAssociations - auth flows don't need domain rewriting
      // This prevents redirect chain issues on mobile browsers during OAuth
    };

    const cloudfrontDist = new cloudfront.Distribution(this, `schengen-calculator`, {
      certificate: certificate.Certificate.fromCertificateArn(this, "sslCertificate", sslCertificateArn),
      domainNames: [customDomain, altDomain],
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      sslSupportMethod: cloudfront.SSLMethod.SNI,
      defaultBehavior: {
        origin: origin,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: authenticatedUserCachePolicy,
        originRequestPolicy: customOriginRequestPolicy,
        functionAssociations
      },
      additionalBehaviors: {
        "/users/*": authFlowBehavior,
        "/*/users/*": authFlowBehavior,
        "assets/*": publicAssetsCacheBehavior,
        "/": publicCacheByCountryGuestBehavior,
        "/en": publicCacheByCountryGuestBehavior,
        "/de": publicCacheByCountryGuestBehavior,
        "/es": publicCacheByCountryGuestBehavior,
        "/tr": publicCacheByCountryGuestBehavior,
        "/zh-CN": publicCacheByCountryGuestBehavior,
        "/hi": publicCacheByCountryGuestBehavior,
        "/pt-BR": publicCacheByCountryGuestBehavior,
        "/about*": publicCacheByCountryGuestBehavior,
        "/*/about*": publicCacheByCountryGuestBehavior,
        "/blog*": publicCacheByCountryGuestBehavior,
        "/*/blog*": publicCacheByCountryGuestBehavior,
        "/robots.txt": publicAssetsCacheBehavior,
        "/sitemap.xml": publicAssetsCacheBehavior,
        "/favicon.ico": publicAssetsCacheBehavior,
        "/med.png": publicAssetsCacheBehavior,
        "/ads.txt": publicAssetsCacheBehavior
      }
    });

    const cloudFrontUrlOutput = new cdk.CfnOutput(this, 'CloudFrontUrl', {
      value: cloudfrontDist.domainName!,
    });
    cloudFrontUrlOutput.overrideLogicalId('CloudFrontUrl');

    const opsLambdaNameOutput = new cdk.CfnOutput(this, 'OpsLambdaFunctionName', {
      value: opsFunction.functionName,
    });
    opsLambdaNameOutput.overrideLogicalId('OpsLambdaFunctionName');
  }
}