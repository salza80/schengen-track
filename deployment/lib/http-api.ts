import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpIamAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { OriginSigner } from './origin-signer';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as apigwv2_integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as certificate from 'aws-cdk-lib/aws-certificatemanager';
import { createRedirectFunction } from './createRedirectFunction';
import { createClientIpFunction } from './createClientIpFunction';
import { McpLambdaConstruct } from './mcp-lambda';
import { schengenCachePolicies, CachePolicyIds } from './cache-policies';

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
  publicCalculatorCacheTtlSeconds?: number,
  cachePolicyIds?: CachePolicyIds
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
    const publicCalculatorCacheTtlSeconds = props.publicCalculatorCacheTtlSeconds ?? cdk.Duration.days(30).toSeconds();
    const cachePolicies = schengenCachePolicies(this, publicCalculatorCacheTtlSeconds, props.cachePolicyIds);
    const agentAuthParamName = `${props.paramPath}secrets/schengen_agent_auth_header`;
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
      defaultAuthorizer: new HttpIamAuthorizer(),
      defaultIntegration: new apigwv2_integ.HttpLambdaIntegration('RailsHttpApiProxy', apiFunction, {
        payloadFormatVersion: apigwv2.PayloadFormatVersion.VERSION_2_0,
        parameterMapping: new apigwv2.ParameterMapping().overwriteHeader("host", apigwv2.MappingValue.custom(customDomain))
      }),
    });

    const mcp = new McpLambdaConstruct(this, 'Mcp', {
      domain: customDomain,
      agentAuthParamName,
      agentAuthParamArn,
      googleAnalyticsApiSecretParamName: gaApiSecretParamName,
      googleAnalyticsApiSecretParamArn: gaApiSecretParamArn,
    });

    const sslCertificateArn = props.sslArn;
    const calculatorReadQuota = new dynamodb.Table(this, 'CalculatorReadQuota', {
      partitionKey: { name: 'bucket', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      timeToLiveAttribute: 'expires_at',
      maxReadRequestUnits: 100,
      maxWriteRequestUnits: 100,
    });
    const signer = new OriginSigner(this, 'OriginSigner', [
      railsHttpApi.arnForExecuteApi(), mcp.httpApi.arnForExecuteApi(),
    ], calculatorReadQuota.tableArn);
    apiFunction.addEnvironment('CLOUDFRONT_SIGNER_ROLE_ARN', signer.roleArn);
    mcp.function.addEnvironment('CLOUDFRONT_SIGNER_ROLE_ARN', signer.roleArn);
    const edgeLambdas = [signer.association];
    // Each behavior selects trusted filtering rules in the origin signer.
    // Forwarding all headers except Host preserves generated SigV4 headers;
    // the signer removes unkeyed viewer headers before they reach Rails.
    const railsOrigin = (profile: string) => new origins.HttpOrigin(
      `${railsHttpApi.apiId}.execute-api.${Stack.of(this).region}.amazonaws.com`, {
        customHeaders: {
          'x-schengen-header-profile': profile,
          'x-schengen-read-quota-table': calculatorReadQuota.tableName,
        },
      });
    const origin = railsOrigin('private');
    const publicOrigin = railsOrigin('public');
    const calculatorOrigin = railsOrigin('calculator');
    const sessionOrigin = railsOrigin('session');
    const authOrigin = railsOrigin('auth');
    const agentOrigin = railsOrigin('agent');
    const mcpOrigin = new origins.HttpOrigin(`${mcp.httpApi.apiId}.execute-api.${Stack.of(this).region}.amazonaws.com`, {
      customHeaders: { 'x-schengen-header-profile': 'mcp' },
    });
    const signedOriginHeaders = cloudfront.OriginRequestHeaderBehavior.denyList('Host');
    const customOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "customDefaultRequestPolicy", {
      headerBehavior: signedOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.allowList('_schengen_track_session', 'has_calculator_session'),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    });
    const publicOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "publicRequestPolicy", {
      headerBehavior: signedOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    });
    const sessionHeaderRequestPolicy = new cloudfront.OriginRequestPolicy(this, "sessionHeaderRequestPolicy", {
      headerBehavior: signedOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.allowList('_schengen_track_session', 'has_calculator_session', 'has_flash_message'),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    });
    const calculatorIndexRequestPolicy = new cloudfront.OriginRequestPolicy(this, "calculatorIndexRequestPolicy", {
      headerBehavior: signedOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    });
    const authOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "authRequestPolicy", {
      headerBehavior: signedOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.all(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    });
    const agentApiOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "agentApiRequestPolicy", {
      headerBehavior: signedOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.all(),
    });
    const mcpOriginRequestPolicy = new cloudfront.OriginRequestPolicy(this, "mcpRequestPolicy", {
      headerBehavior: signedOriginHeaders,
      cookieBehavior: cloudfront.OriginRequestCookieBehavior.none(),
      queryStringBehavior: cloudfront.OriginRequestQueryStringBehavior.none(),
    });

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

    // Allow aggressive browser caching for fingerprinted static assets.
    const assetsBrowserCachePolicy = new cloudfront.ResponseHeadersPolicy(this, "assetsBrowserCache", {
      customHeadersBehavior: {
        customHeaders: [{
          header: 'Cache-Control',
          value: 'public, max-age=31536000, immutable',
          override: true
        }]
      }
    });

    const namedAssetBrowserCachePolicy = new cloudfront.ResponseHeadersPolicy(this, "namedAssetBrowserCache", {
      customHeadersBehavior: {
        customHeaders: [{
          header: 'Cache-Control',
          value: 'public, max-age=604800, must-revalidate',
          override: true
        }]
      }
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
    const authClientIpFunction = new cloudfront.Function(this, 'authClientIpFunction', {
      code: cloudfront.FunctionCode.fromInline(createClientIpFunction())
    });

    const publicHtmlBehavior = {
      origin: publicOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cachePolicies.publicHtml,
      originRequestPolicy: publicOriginRequestPolicy,
      responseHeadersPolicy: customNoBrowserHeaderResponsePolicy,
      functionAssociations
    };

    const sessionHeaderBehavior = {
      origin: sessionOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: sessionHeaderRequestPolicy,
      functionAssociations
    };

    const csrfTokenBehavior = {
      origin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: customOriginRequestPolicy,
      functionAssociations
    };

    const tripsIndexBehavior = {
      origin: calculatorOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cachePolicies.tripsIndex,
      originRequestPolicy: calculatorIndexRequestPolicy,
      responseHeadersPolicy: calculatorNoBrowserCachePolicy,
      functionAssociations
    };

    const calendarIndexBehavior = {
      origin: calculatorOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cachePolicies.calendarIndex,
      originRequestPolicy: calculatorIndexRequestPolicy,
      responseHeadersPolicy: calculatorNoBrowserCachePolicy,
      functionAssociations
    };

    const publicAssetsCacheBehavior = {
      origin: publicOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cachePolicies.immutableAssets,
      originRequestPolicy: publicOriginRequestPolicy,
      responseHeadersPolicy: assetsBrowserCachePolicy,
      functionAssociations
    };

    const publicNamedAssetCacheBehavior = {
      origin: publicOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cachePolicies.namedAsset,
      originRequestPolicy: publicOriginRequestPolicy,
      responseHeadersPolicy: namedAssetBrowserCachePolicy,
      functionAssociations
    };

    const publicSeoDocsCacheBehavior = {
      origin: publicOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cachePolicies.publicHtml,
      originRequestPolicy: publicOriginRequestPolicy,
      responseHeadersPolicy: seoDocsBrowserCachePolicy,
      functionAssociations
    };

    const authFlowBehavior = {
      origin: authOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: authOriginRequestPolicy,
      // Preserve OAuth's URL/redirect chain while overwriting viewer identity.
      functionAssociations: [{ function: authClientIpFunction, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST }]
    };

    const agentApiBehavior = {
      origin: agentOrigin,
      edgeLambdas,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: agentApiOriginRequestPolicy,
      functionAssociations
    };

    const mcpBehavior = {
      origin: mcpOrigin,
      edgeLambdas,
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
        edgeLambdas,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cachePolicies.authenticatedUser,
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
        "/favicon.ico": publicNamedAssetCacheBehavior,
        "/med.png": publicNamedAssetCacheBehavior,
        "/ads.txt": publicSeoDocsCacheBehavior
      }
    });

    cloudfrontDist.node.addDependency(signer.invokePolicy);

    new cdk.CfnOutput(this, 'RailsOriginUrl', { value: railsHttpApi.apiEndpoint }).overrideLogicalId('RailsOriginUrl');
    new cdk.CfnOutput(this, 'McpOriginUrl', { value: mcp.httpApi.apiEndpoint }).overrideLogicalId('McpOriginUrl');

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
