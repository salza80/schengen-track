import { CodePipeline, CodePipelineSource, ShellStep } from 'aws-cdk-lib/pipelines';
import { Construct } from 'constructs';
import {  Stack, StackProps } from 'aws-cdk-lib';
import { CdkEBStage } from './eb-stage';

export class CdkPipelineStack extends Stack {
  constructor(scope: Construct, id: string, props: StackProps) {
    super(scope, id, props);

    const pipeline = new CodePipeline(this, 'Pipeline', {
      // The pipeline name
      pipelineName: 'schengenTrackCdkPipeline',

       // How it will be built and synthesized
       synth: new ShellStep('Synth', {
         // Where the source can be found
         input: CodePipelineSource.gitHub('salza80/schengen-track', 'cdkElasticDeploy'),
         
         // Install dependencies, build and run cdk synth
         installCommands: ['npm i -g npm@latest'],
         commands: [
           'cd deployment',
           'npm ci',
           'npm run build',
           'npm run cdk synth',
         ],
         primaryOutputDirectory: 'deployment/cdk.out'
       }),
    });

    // This is where we add the application stages

    // For environment with custom AutoScaling group configuration
    const deploy = new CdkEBStage(this, 'Prod4', { 
        minSize : "1",
        maxSize : "1",
        envName : "Prod4",
        dbDeletionPolicy: 'Delete',
        secretsArn : "arn:aws:secretsmanager:eu-central-1:360298971790:secret:prod/schengTrack/secrets-gU94YO",
        certificateArn : "arn:aws:acm:eu-central-1:360298971790:certificate/7432e75e-3fe7-44a8-89fd-0b66d04d2cec",
    });

    const deployStage = pipeline.addStage(deploy);

  }
}