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
import { McpLambdaConstruct } from './mcp-lambda';

import { Platform } from 'aws-cdk-lib/aws-ecr-assets';

import * as path from 'path';
// import { SmsSubscription } from 'aws-cdk-lib/aws-sns-subscriptions';
import { Stack } from 'aws-cdk-lib';

export interface HttpApiConstructProps {
  domain: string,
  altDomain: string,
  sslArn: string,
  paramPath: string,
  facebookWebLoginWorkaround?: boolean,
  publicCalculatorCacheTtlSeconds?: number
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
    const publicCalculatorCacheTtlSeconds = props.publicCalculatorCacheTtlSeconds ?? 86400;
    const cloudFrontOriginAuthParamName = `${props.paramPath}cloudfront_origin_auth_header`;
    const agentAuthParamName = `${props.paramPath}secrets/schengen_agent_auth_header`;
    // CloudFront origin custom headers do not support ssm-secure dynamic
    // references, so this value is stored as an SSM String. Lambdas receive
    // only parameter names and read values at runtime with ssm:GetParameter.
    const cloudFrontOriginAuthHeader = cdk.Token.asString(new cdk.CfnDynamicReference(
      cdk.CfnDynamicReferenceService.SSM,
      cloudFrontOriginAuthParamName
    ));
    const cfRewriteUrlFunction = new cloudfront.Function(this, 'rewriteUrl', {
      code: cloudfront.FunctionCode.fromInline(createRedirectFunction(altDomain, customDomain))
    });

    const getParam = (paramName: string) => ssm.StringParameter.valueForStringParameter(
      this, `${props.paramPath}${paramName}`);
    const gaApiSecretParamName = `${props.paramPath}secrets/ga_api_secret`;
    const pooledDbUrlParamName = `${props.paramPath}secrets/db_pooler_url`;
    const directDbUrlParamName = `${props.paramPath}secrets/db_direct_url`;
    const runtimeSecretParamNames = {
      railsMasterKey: `${props.paramPath}secrets/rails_master_key`,
      secretKeyBase: `${props.paramPath}secrets/secret_key_base`,
      facebookSecret: `${props.paramPath}secrets/facebook_secret`,
      brevoPassword: `${props.paramPath}secrets/brevo_password`,
    };
    const ssmParamArn = (paramName: string) => `arn:aws:ssm:${Stack.of(this).region}:${Stack.of(this).account}:parameter${paramName}`;
    const gaApiSecretParamArn = ssmParamArn(gaApiSecretParamName);
    const cloudFrontOriginAuthParamArn = ssmParamArn(cloudFrontOriginAuthParamName);
    const agentAuthParamArn = ssmParamArn(agentAuthParamName);
    const pooledDbUrlParamArn = ssmParamArn(pooledDbUrlParamName);
    const directDbUrlParamArn = ssmParamArn(directDbUrlParamName);
    const runtimeSecretParamArns = Object.values(runtimeSecretParamNames).map(ssmParamArn);


    // Values required while the production Rails application boots. Facebook
    // and Brevo remain here because their Rails initializers read them during
    // boot, including when the Ops handler loads the application.
    const railsBootEnvironment = {
      BOOTSNAP_CACHE_DIR: '/tmp/cache',
      RAILS_ENV: 'production',
      RAILS_MASTER_KEY_PARAM: runtimeSecretParamNames.railsMasterKey,
      RAILS_LOG_TO_STDOUT: '1',
      SECRET_KEY_BASE_PARAM: runtimeSecretParamNames.secretKeyBase,
      FACEBOOK_ID: getParam('facebook_id'),
      FACEBOOK_SECRET_PARAM: runtimeSecretParamNames.facebookSecret,
      FACEBOOK_CALLBACK_URL: getParam('facebook_callback_url'),
      FACEBOOK_WEB_LOGIN_WORKAROUND: String(props.facebookWebLoginWorkaround ?? false),
      PUBLIC_CALCULATOR_CACHE_TTL: String(publicCalculatorCacheTtlSeconds),
      BREVO_LOGIN: getParam('brevo_login'),
      BREVO_PASSWORD_PARAM: runtimeSecretParamNames.brevoPassword,
      DOMAIN: customDomain,
    };

    // Request-only configuration belongs on the HTTP API Lambda, not the
    // administrative Ops Lambda.
    const apiContainerEnvironment = {
      ...railsBootEnvironment,
      DB_URL_PARAM: pooledDbUrlParamName,
      GA_MEASUREMENT_ID: 'G-E9CCZDHLJF',
      GA_API_SECRET_PARAM: gaApiSecretParamName,
      CLOUDFRONT_ORIGIN_AUTH_PARAM: cloudFrontOriginAuthParamName,
      SCHENGEN_AGENT_AUTH_PARAM: agentAuthParamName,
    };

    const opsContainerEnvironment = {
      ...railsBootEnvironment,
      DB_URL_PARAM: directDbUrlParamName,
      PGCONNECT_TIMEOUT: '10',
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
      environment: opsContainerEnvironment,
      timeout: cdk.Duration.minutes(15),
      reservedConcurrentExecutions: 1,
      tracing: lambda.Tracing.ACTIVE,
    });

    apiFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['ssm:GetParameter', 'ssm:GetParameters'],
      resources: [
        gaApiSecretParamArn,
        cloudFrontOriginAuthParamArn,
        agentAuthParamArn,
        pooledDbUrlParamArn,
        ...runtimeSecretParamArns,
      ]
    }));

    opsFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['ssm:GetParameters'],
      resources: [
        directDbUrlParamArn,
        ...runtimeSecretParamArns,
      ]
    }));

    // Grant Lambda permission to read the deployment timestamp from Parameter Store
    apiFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['ssm:GetParameter'],
      resources: [
        `arn:aws:ssm:${Stack.of(this).region}:${Stack.of(this).account}:parameter/schengen/deployment-timestamp`
      ]
    }));

    // AWS API Gateway HTTP API using Rails as Lambda proxy integration
    // overwrite host header with domain, as it will come from cloudfront and rails requires it for security xss checks.
    const railsHttpApi = new apigwv2.HttpApi(this, 'Api', {
      apiName: 'RailsHttpApi',
      defaultIntegration: new apigwv2_integ.HttpLambdaIntegration('RailsHttpApiProxy', apiFunction, {
        payloadFormatVersion: apigwv2.PayloadFormatVersion.VERSION_2_0,
        parameterMapping: new apigwv2.ParameterMapping().overwriteHeader("host", apigwv2.MappingValue.custom(customDomain))
      }),
    });

    const mcp = new McpLambdaConstruct(this, 'Mcp', {
      domain: customDomain,
      agentAuthParamName,
      agentAuthParamArn,
      cloudFrontOriginAuthParamName,
      cloudFrontOriginAuthParamArn,
      googleAnalyticsApiSecretParamName: gaApiSecretParamName,
      googleAnalyticsApiSecretParamArn: gaApiSecretParamArn,
    });

    const sslCertificateArn = props.sslArn;
    const originCustomHeaders = {
      'X-Schengen-Origin-Auth': cloudFrontOriginAuthHeader,
    };
    const origin = new origins.HttpOrigin(`${railsHttpApi.apiId}.execute-api.${Stack.of(this).region}.amazonaws.com`, {
      customHeaders: originCustomHeaders,
    });
    const mcpOrigin = new origins.HttpOrigin(`${mcp.httpApi.apiId}.execute-api.${Stack.of(this).region}.amazonaws.com`, {
      customHeaders: originCustomHeaders,
    });
    const publicOriginHeaders = cloudfront.OriginRequestHeaderBehavior.allowList(
        'Origin', 
        'Access-Control-Request-Method', 
        'Access-Control-Request-Headers',
        'Accept',
        'Content-Type',
        'X-Requested-With',
        'Referer',
        'X-Schengen-Client-Ip'
      );
    // The calculator indexes share one HTML cache variant. Do not forward
    // content-negotiation headers such as Accept unless they are also part of
    // the cache key, or a CSV response could populate the HTML cache entry.
    const calculatorIndexOriginHeaders = cloudfront.OriginRequestHeaderBehavior.allowList(
        'Origin',
        'Access-Control-Request-Method',
        'Access-Control-Request-Headers',
        'Content-Type',
        'X-Requested-With',
        'Referer',
        'X-Schengen-Client-Ip'
      );
    const customOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "customDefaultRequestPolicy", {
      headerBehavior: publicOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.allowList('_schengen_track_session', 'has_calculator_session'),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    })

    // Parameters excluded from the public cache key must not influence the
    // origin response (e.g. ?nationality=American can redirect the homepage).
    const publicOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "publicRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.none(),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    });

    const sessionHeaderRequestPolicy = new cloudfront.OriginRequestPolicy(this, "sessionHeaderRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.none(),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.allowList('_schengen_track_session', 'has_calculator_session', 'has_flash_message'),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    });

    const calculatorIndexRequestPolicy = new cloudfront.OriginRequestPolicy(this, "calculatorIndexRequestPolicy", {
      headerBehavior: calculatorIndexOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    });

    // Separate policy for authentication flows that need all cookies for CSRF
    const authOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "authRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.allowList(
        'Origin', 
        'Access-Control-Request-Method', 
        'Access-Control-Request-Headers',
        'Accept',
        'X-Requested-With',
        'Referer',
        'X-Schengen-Client-Ip'
      ),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.all(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    })

    // Dedicated policy for the public calculation API. It forwards the private
    // MCP-to-Rails headers without pushing the general/auth policies over the
    // CloudFront header allow-list quota.
    const agentApiOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "agentApiRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.allowList(
        'Origin',
        'Access-Control-Request-Method',
        'Access-Control-Request-Headers',
        'X-Schengen-Client-Ip',
        'X-Schengen-Agent-Source',
        'X-Schengen-Agent-Auth',
        'X-Schengen-Agent-Client-Id'
      ),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    })

    const mcpOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "mcpRequestPolicy", {
      headerBehavior: cloudfront.OriginRequestHeaderBehavior.allowList(
        'Accept',
        'Content-Type',
        'Mcp-Protocol-Version',
        'Mcp-Session-Id',
        'X-Schengen-Client-Ip'
      ),
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    })

    const publicHtmlCachePolicy = new cloudfront.CachePolicy(this, "publicHtmlCachePolicy", {
      headerBehavior: cloudfront.CacheHeaderBehavior.none(),
      cookieBehavior: cloudfront.CacheCookieBehavior.none(),
      // Public HTML pages are selected entirely by their path/locale. Ignore
      // tracking and other incidental query parameters so bots cannot
      // fragment the cache with effectively identical URLs.
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
      enableAcceptEncodingBrotli: true,
      enableAcceptEncodingGzip: true,
      minTtl: cdk.Duration.seconds(0),
      defaultTtl: cdk.Duration.hours(1),
      maxTtl: cdk.Duration.days(1)
    })

    const calculatorCachePolicyProps = {
      headerBehavior: cloudfront.CacheHeaderBehavior.none(),
      cookieBehavior: cloudfront.CacheCookieBehavior.allowList('_schengen_track_session', 'has_calculator_session'),
      enableAcceptEncodingBrotli: true,
      enableAcceptEncodingGzip: true,
      minTtl: cdk.Duration.seconds(0),
      defaultTtl: cdk.Duration.seconds(publicCalculatorCacheTtlSeconds),
      // Maximum TTL caps both fresh and stale delivery. Add the fresh window
      // so the full seven-day stale period remains available.
      maxTtl: cdk.Duration.seconds(publicCalculatorCacheTtlSeconds + cdk.Duration.days(7).toSeconds()),
    };

    const tripsIndexCachePolicy = new cloudfront.CachePolicy(this, "tripsIndexCachePolicy", {
      ...calculatorCachePolicyProps,
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
    });

    const calendarIndexCachePolicy = new cloudfront.CachePolicy(this, "calendarIndexCachePolicy", {
      ...calculatorCachePolicyProps,
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.allowList('year'),
    });

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

    // Calculator index responses can be public or session-specific. Keep them
    // out of the browser cache without stripping cookies from private responses.
    const calculatorNoBrowserCachePolicy = new cloudfront.ResponseHeadersPolicy(this, "calculatorNoBrowserCache", {
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

    const seoDocsCachePolicy = new cloudfront.CachePolicy(this, "seoDocsCache", {
      headerBehavior: cloudfront.CacheHeaderBehavior.none(),
      cookieBehavior: cloudfront.CacheCookieBehavior.none(),
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
      enableAcceptEncodingBrotli: true,
      enableAcceptEncodingGzip: true,
      minTtl: cdk.Duration.seconds(0),
      maxTtl: cdk.Duration.days(1),
      defaultTtl: cdk.Duration.hours(1)
    });

    const seoDocsBrowserCachePolicy = new cloudfront.ResponseHeadersPolicy(this, "seoDocsBrowserCache", {
      customHeadersBehavior: {
        customHeaders: [{
          header: 'Cache-Control',
          value: 'public, max-age=3600, must-revalidate',
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

    const publicHtmlBehavior = {
      origin: origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: publicHtmlCachePolicy,
      originRequestPolicy: publicOriginRequestPolicy,
      responseHeadersPolicy: customNoBrowserHeaderResponsePolicy,
      functionAssociations
    };

    const sessionHeaderBehavior = {
      origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: sessionHeaderRequestPolicy,
      functionAssociations
    };

    const csrfTokenBehavior = {
      origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: customOriginRequestPolicy,
      functionAssociations
    };

    const tripsIndexBehavior = {
      origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: tripsIndexCachePolicy,
      originRequestPolicy: calculatorIndexRequestPolicy,
      responseHeadersPolicy: calculatorNoBrowserCachePolicy,
      functionAssociations
    };

    const calendarIndexBehavior = {
      origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: calendarIndexCachePolicy,
      originRequestPolicy: calculatorIndexRequestPolicy,
      responseHeadersPolicy: calculatorNoBrowserCachePolicy,
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

    const publicSeoDocsCacheBehavior = {
      origin: origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: seoDocsCachePolicy,
      responseHeadersPolicy: seoDocsBrowserCachePolicy,
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

    const agentApiBehavior = {
      origin: origin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: agentApiOriginRequestPolicy,
      functionAssociations
    };

    const mcpBehavior = {
      origin: mcpOrigin,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: mcpOriginRequestPolicy,
      functionAssociations
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
        "/mcp*": mcpBehavior,
        "/api/v1/calculations*": agentApiBehavior,
        "/users/*": authFlowBehavior,
        "/*/users/*": authFlowBehavior,
        "/session_header": sessionHeaderBehavior,
        "/*/session_header": sessionHeaderBehavior,
        "/csrf_token": csrfTokenBehavior,
        "/*/csrf_token": csrfTokenBehavior,
        "/visits": tripsIndexBehavior,
        "/*/visits": tripsIndexBehavior,
        "/days": calendarIndexBehavior,
        "/*/days": calendarIndexBehavior,
        "assets/*": publicAssetsCacheBehavior,
        "/": publicHtmlBehavior,
        "/en": publicHtmlBehavior,
        "/de": publicHtmlBehavior,
        "/es": publicHtmlBehavior,
        "/tr": publicHtmlBehavior,
        "/zh-CN": publicHtmlBehavior,
        "/hi": publicHtmlBehavior,
        "/pt-BR": publicHtmlBehavior,
        "/fr": publicHtmlBehavior,
        "/ar": publicHtmlBehavior,
        "/about*": publicHtmlBehavior,
        "/*/about*": publicHtmlBehavior,
        "/blog*": publicHtmlBehavior,
        "/*/blog*": publicHtmlBehavior,
        "/disclaimer*": publicSeoDocsCacheBehavior,
        "/*/disclaimer*": publicSeoDocsCacheBehavior,
        "/privacy*": publicSeoDocsCacheBehavior,
        "/*/privacy*": publicSeoDocsCacheBehavior,
        "/datadeletion*": publicSeoDocsCacheBehavior,
        "/*/datadeletion*": publicSeoDocsCacheBehavior,
        "/api/docs": publicSeoDocsCacheBehavior,
        "/robots.txt": publicSeoDocsCacheBehavior,
        "/llms.txt": publicSeoDocsCacheBehavior,
        "/llms-full.txt": publicSeoDocsCacheBehavior,
        "/openapi.json": publicSeoDocsCacheBehavior,
        "/sitemap*": publicSeoDocsCacheBehavior,
        "/favicon.ico": publicAssetsCacheBehavior,
        "/med.png": publicAssetsCacheBehavior,
        "/ads.txt": publicSeoDocsCacheBehavior
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
