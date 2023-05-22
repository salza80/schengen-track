import {  Stage } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { EBEnvProps, EBApplnStack } from './eb-appln-stack';

/**
 * Deployable unit of web service app
 */
export class CdkEBStage extends Stage {
      
  constructor(scope: Construct, id: string, props?: EBEnvProps) {
    super(scope, id, props);

    const service = new EBApplnStack(this, 'WebService', {
        minSize : props?.minSize, 
        maxSize : props?.maxSize,
        instanceTypes : props?.instanceTypes,
        envName : props?.envName
    } );

  }
}