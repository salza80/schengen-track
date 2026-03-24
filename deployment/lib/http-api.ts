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
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53Targets from 'aws-cdk-lib/aws-route53-targets';
import { createRedirectFunction } from './createRedirectFunction';

import { Platform } from 'aws-cdk-lib/aws-ecr-assets';

import * as path from 'path';
// import { SmsSubscription } from 'aws-cdk-lib/aws-sns-subscriptions';
import { Stack } from 'aws-cdk-lib';

export interface HttpApiConstructProps {
  domain: string,
  altDomain: string,
  sslArn: string,
  paramPath: string,
  hostedZoneId: string,
  hostedZoneName: string,
  createSharedDnsRecords: boolean
}

interface CnameRecordDefinition {
  recordName: string,
  domainName: string,
  ttl?: cdk.Duration
}

interface TxtRecordDefinition {
  recordName: string,
  values: string[],
  ttl?: cdk.Duration
}

const EXISTING_RECORD_TTL = cdk.Duration.seconds(300);

const sharedProductionCnameRecords: CnameRecordDefinition[] = [
  {
    recordName: '_215e781da24efe9ddff2bc347a77fc9f',
    domainName: '_4c05f2c064fcaba386ecbfd5c3411c72.dnzkjbsjxj.acm-validations.aws.',
    ttl: cdk.Duration.minutes(30)
  },
  {
    recordName: '_2e040d9384a5c18a2cf172c3675dfdc9',
    domainName: '_6b1f4803ca9baf222e56d38c6d5e3468.dnzkjbsjxj.acm-validations.aws.',
    ttl: cdk.Duration.minutes(10)
  },
  {
    recordName: '_b4abeb352c0fe2e73390c6a1ad924d8d',
    domainName: '_e9c79ecd3d992ae9acc504bf239a8876.dnzkjbsjxj.acm-validations.aws.',
    ttl: cdk.Duration.minutes(10)
  },
  {
    recordName: '_215e781da24efe9ddff2bc347a77fc9f.www',
    domainName: '_4c05f2c064fcaba386ecbfd5c3411c72.dnzkjbsjxj.acm-validations.aws.',
    ttl: cdk.Duration.minutes(30)
  },
  {
    recordName: 'brevo1._domainkey',
    domainName: 'b1.schengen-calculator-com.dkim.brevo.com',
    ttl: cdk.Duration.minutes(5)
  },
  {
    recordName: 'brevo2._domainkey',
    domainName: 'b2.schengen-calculator-com.dkim.brevo.com',
    ttl: cdk.Duration.minutes(5)
  }
];

const sharedProductionTxtRecords: TxtRecordDefinition[] = [
  {
    recordName: '',
    values: [
      'google-site-verification=bpQ0Yeqh2zLoLeFBT5hYXAYMishcxLS1F353hnNT6rM',
      'google-site-verification=UyjvLv9o3tg3xvM4GM_n9MGknCIrAt6kG33515EKWaE',
      'brevo-code:f476b8e875f757bb0d6a3ccbd2c912ec',
      'forward-email=smclean17@gmail.com'
    ],
    ttl: cdk.Duration.hours(1)
  },
  {
    recordName: '_dmarc',
    values: ['v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com'],
    ttl: cdk.Duration.minutes(5)
  }
];
/**
 * CDK construct to create API Gateway HTTP API with Lambda proxy integration 2.0
 */
export class HttpApiConstruct extends Construct {
  /**
   * Create API Gateway HTTP API with Lambda proxy integration 2.0
   */
  constructor(scope: Construct, id: string, props: HttpApiConstructProps) {
    super(scope, id);

    const hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
      hostedZoneId: props.hostedZoneId,
      zoneName: props.hostedZoneName
    });

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

    const aliasTarget = route53.RecordTarget.fromAlias(new route53Targets.CloudFrontTarget(cloudfrontDist));
    const aliasRecordNames = [customDomain, altDomain];

    // These records already exist in the hosted zone today, so the first managed deploy
    // needs to replace the manual records before CloudFormation can own them.
    aliasRecordNames.forEach((recordName) => {
      const normalizedRecordName = normalizeRecordName(recordName, props.hostedZoneName);
      const recordId = recordIdSuffix(recordName);

      new route53.ARecord(this, `${recordId}AliasARecord`, {
        zone: hostedZone,
        recordName: normalizedRecordName,
        target: aliasTarget,
        deleteExisting: true
      });

      new route53.AaaaRecord(this, `${recordId}AliasAaaaRecord`, {
        zone: hostedZone,
        recordName: normalizedRecordName,
        target: aliasTarget
      });
    });

    if (props.createSharedDnsRecords) {
      new route53.MxRecord(this, 'RootMxRecord', {
        zone: hostedZone,
        values: [
          { priority: 0, hostName: 'mx1.forwardemail.net.' },
          { priority: 10, hostName: 'mx2.forwardemail.net.' }
        ],
        ttl: cdk.Duration.hours(1),
        deleteExisting: true
      });

      sharedProductionTxtRecords.forEach((record) => {
        new route53.TxtRecord(this, `${recordIdSuffix(record.recordName || 'root')}TxtRecord`, {
          zone: hostedZone,
          recordName: record.recordName || undefined,
          values: record.values,
          ttl: record.ttl ?? EXISTING_RECORD_TTL,
          deleteExisting: true
        });
      });

      sharedProductionCnameRecords.forEach((record) => {
        new route53.CnameRecord(this, `${recordIdSuffix(record.recordName)}CnameRecord`, {
          zone: hostedZone,
          recordName: record.recordName,
          domainName: record.domainName,
          ttl: record.ttl ?? EXISTING_RECORD_TTL,
          deleteExisting: true
        });
      });
    }

    const opsLambdaNameOutput = new cdk.CfnOutput(this, 'OpsLambdaFunctionName', {
      value: opsFunction.functionName,
    });
    opsLambdaNameOutput.overrideLogicalId('OpsLambdaFunctionName');
  }
}

function normalizeRecordName(recordName: string, zoneName: string): string | undefined {
  if (recordName === zoneName) {
    return undefined;
  }

  const zoneSuffix = `.${zoneName}`;
  return recordName.endsWith(zoneSuffix)
    ? recordName.slice(0, -zoneSuffix.length)
    : recordName;
}

function recordIdSuffix(recordName: string): string {
  return recordName
    .replace(/\./g, '-')
    .replace(/[^A-Za-z0-9-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '') || 'root';
}
