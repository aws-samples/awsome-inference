import * as path from 'path';
import { Duration } from 'aws-cdk-lib';
import { Effect, PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { Runtime } from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { RetentionDays } from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export class RegisterTargetsFunction extends Construct {
  public lambdaFunction: NodejsFunction;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    this.lambdaFunction = new NodejsFunction(this, 'RegisterTargetsLambda', {
      entry: path.join(__dirname, 'resources/registerTargets/index.ts'),
      handler: 'handler',
      runtime: Runtime.NODEJS_18_X,
      timeout: Duration.minutes(5),
      logRetention: RetentionDays.ONE_WEEK,
    });

    this.lambdaFunction.addToRolePolicy(
      new PolicyStatement({
        effect: Effect.ALLOW,
        actions: ['autoscaling:DescribeAutoScalingGroups'],
        resources: ['*'],
      }),
    );
  }
}
