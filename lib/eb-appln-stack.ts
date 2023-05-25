import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
// import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as elasticbeanstalk from 'aws-cdk-lib/aws-elasticbeanstalk';
import * as s3assets from 'aws-cdk-lib/aws-s3-assets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import { Secret } from "aws-cdk-lib/aws-secretsmanager";

export interface EBEnvProps extends cdk.StackProps {
    // Autoscaling group configuration
  minSize?: string;
  maxSize?: string;
  instanceTypes?: string;
  envName?: string;
  envVariables?: { name: string, value: string }[];
}

export class EBApplnStack extends cdk.Stack {
   constructor(scope: Construct, id: string, props?: EBEnvProps) {
    super(scope, id, props);

    // The code that defines your stack goes here

    // example resource
    // const queue = new sqs.Queue(this, 'CdkQueue', {
    //   visibilityTimeout: cdk.Duration.seconds(300)
    // });

    // Construct an S3 asset Zip from directory up.
    // const webAppZipArchive = new s3assets.Asset(this, 'WebAppZip', {
    //   path: `${__dirname}/../src`,
    // });

    const certificateArn = 'arn:aws:acm:eu-central-1:360298971790:certificate/f3900bfd-15ff-44a3-a1c1-56eee654c19e';
    const sslCertificate = acm.Certificate.fromCertificateArn(this, 'MySSLCertificate', certificateArn);

    const webAppZipArchive = new s3assets.Asset(this, 'WebAppZip', {
        path: `${__dirname}/../app.zip`,
    });


    const appName = 'cdkSchengTrack';
    const app = new elasticbeanstalk.CfnApplication(this, 'Application', {
        applicationName: appName,
    });

    // Create an app version from the S3 asset defined earlier
    const appVersionProps = new elasticbeanstalk.CfnApplicationVersion(this, 'AppVersion', {
        applicationName: appName,
        sourceBundle: {
            s3Bucket: webAppZipArchive.s3BucketName,
            s3Key: webAppZipArchive.s3ObjectKey,
        },
    });

    // Make sure that Elastic Beanstalk app exists before creating an app version
    appVersionProps.addDependency(app);

    // Create role and instance profile
    const myRole = new iam.Role(this, `${appName}-aws-elasticbeanstalk-ec2-role`, {
        assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
    });

    const managedPolicy = iam.ManagedPolicy.fromAwsManagedPolicyName('AWSElasticBeanstalkWebTier')
    myRole.addManagedPolicy(managedPolicy);

    const myProfileName = `${appName}-InstanceProfile`

    const instanceProfile = new iam.CfnInstanceProfile(this, myProfileName, {
        instanceProfileName: myProfileName,
        roles: [
            myRole.roleName
        ]
    });

    const rdsNamespace = "aws:rds:dbinstance";

    const secret = Secret.fromSecretAttributes(this, "schenTrackRailsSecrets", {
      secretCompleteArn:
        "arn:aws:secretsmanager:eu-central-1:360298971790:secret:prod/schengTrack/secrets-gU94YO"
    });


    // Elastic beanstalk configeration
    const optionSettingProperties = [
            {
                namespace: 'aws:elasticbeanstalk:application:environment',
                optionName: 'SecretKeyBase',
                value: secret.secretValueFromJson('secret_key_base').unsafeUnwrap(),
            },
            {
                namespace: 'aws:autoscaling:launchconfiguration',
                optionName: 'IamInstanceProfile',
                value: myProfileName,
            },
            {
                namespace: 'aws:autoscaling:asg',
                optionName: 'MinSize',
                value: props?.maxSize ?? '1',
            },
            {
                namespace: 'aws:autoscaling:asg',
                optionName: 'MaxSize',
                value: props?.maxSize ?? '1',
            },
            {
                namespace: 'aws:ec2:instances',
                optionName: 'InstanceTypes',
                value: props?.instanceTypes ?? 't2.micro',
            },
            {
                namespace: 'aws:ec2:instances',
                optionName: 'EnableSpot',
                value: 'true',
            },
            {
                namespace: rdsNamespace,
                optionName: 'HasCoupledDatabase',
                value: 'true',
            },
            {
                namespace: rdsNamespace,
                optionName: 'DBEngine',
                value: 'postgres',
            },
            {
                namespace: rdsNamespace,
                optionName: 'DBEngineVersion',
                value: '14.6',
            },
            {
                namespace: rdsNamespace,
                optionName: 'DBUser',
                value: 'appUser',
            },
            {
                namespace: rdsNamespace,
                optionName: 'DBPassword',
                value: 'Testing1234*',
            },
            {
                namespace: rdsNamespace,
                optionName: 'DBDeletionPolicy',
                value: 'Delete',
            },
           {
                namespace: rdsNamespace,
                optionName: 'DBInstanceClass',
                value: 'db.t3.micro',
            },
            {
                namespace: rdsNamespace,
                optionName: 'DBAllocatedStorage',
                value: '10',
            },
            // {
            //     namespace: 'aws:elb:listener:443',
            //     optionName: 'ListenerPort',
            //     value: '443',
            // },
            {
                namespace: 'aws:elb:listener',
                optionName: 'ListenerEnabled',
                value: 'false',
            },
            {
                namespace: 'aws:elb:listener:443',
                optionName: 'ListenerProtocol',
                value: 'HTTPS',
            },
            {
                namespace: 'aws:elb:listener:443',
                optionName: 'InstanceProtocol',
                value: 'HTTP',
            },
            {
                namespace: 'aws:elb:listener:443',
                optionName: 'InstancePort',
                value: '80',
            },
            // {
            //     namespace: 'aws:elasticbeanstalk:application',
            //     optionName: 'ApplicationHealthcheckURL',
            //     value: 'HTTPS:443/',
            // },
            {
              namespace: 'aws:elb:listener:443',
              optionName: 'SSLCertificateId',
              value: certificateArn,
            }
        ];


        let l = props?.envVariables?.length || 0;
        for (var i = 0; i < l; i++) {
            var config = props?.envVariables?.[i];
            if (!config) { continue; }
            optionSettingProperties.push(
                {
                    namespace: 'aws:elasticbeanstalk:application:environment',
                    optionName: config.name,
                    value: config.value 
                }
            )
        }

        const envName = props?.envName ?? "MyWebAppEnvironment"
        // Create an Elastic Beanstalk environment to run the application
        const elbEnv = new elasticbeanstalk.CfnEnvironment(this, 'Environment', {
            environmentName: envName,
            applicationName: app.applicationName || appName,
            solutionStackName: '64bit Amazon Linux 2 v3.6.7 running Ruby 3.0',
            optionSettings: optionSettingProperties,
            versionLabel: appVersionProps.ref,
        });

  }
}
