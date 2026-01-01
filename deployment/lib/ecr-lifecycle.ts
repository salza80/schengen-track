import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import { Stack } from 'aws-cdk-lib';

/**
 * Configure ECR lifecycle policy for CDK asset repository
 * This should only be created once per account/region since the repository is shared
 */
export class EcrLifecycleConstruct extends Construct {
  constructor(scope: Construct, id: string) {
    super(scope, id);

    // Reference the CDK bootstrap ECR repository
    const ecrRepository = ecr.Repository.fromRepositoryName(
      this,
      'CDKAssetsRepository',
      `cdk-hnb659fds-container-assets-${Stack.of(this).account}-${Stack.of(this).region}`
    );

    // Keep only the 5 most recent images
    ecrRepository.addLifecycleRule({
      description: 'Keep only the 5 most recent images',
      maxImageCount: 5,
      rulePriority: 1,
    });
  }
}
