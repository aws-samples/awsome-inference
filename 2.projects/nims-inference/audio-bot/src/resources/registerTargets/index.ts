import {
  AutoScalingClient,
  DescribeAutoScalingGroupsCommand,
} from '@aws-sdk/client-auto-scaling';
import {
  ElasticLoadBalancingV2Client,
  RegisterTargetsCommand,
} from '@aws-sdk/client-elastic-load-balancing-v2';
import { CdkCustomResourceEvent, CdkCustomResourceResponse } from 'aws-lambda';

const autoScalingClient = new AutoScalingClient({});
const elbv2Client = new ElasticLoadBalancingV2Client({});

export const handler = async (
  event: CdkCustomResourceEvent,
): Promise<CdkCustomResourceResponse> => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  const autoScalingGroupName = event.ResourceProperties.AutoScalingGroupName;
  const targetGroupArn = event.ResourceProperties.TargetGroupArn;

  if (!autoScalingGroupName || !targetGroupArn) {
    return {
      Status: 'FAILED',
      Reason: 'Missing required properties',
      PhysicalResourceId: event.LogicalResourceId,
    };
  }

  try {
    const asgResponse = await autoScalingClient.send(
      new DescribeAutoScalingGroupsCommand({
        AutoScalingGroupNames: [autoScalingGroupName],
      }),
    );

    const instanceIds =
      asgResponse.AutoScalingGroups?.[0].Instances?.map(
        (instance) => instance.InstanceId,
      ) || [];

    if (instanceIds.length > 0) {
      await elbv2Client.send(
        new RegisterTargetsCommand({
          TargetGroupArn: targetGroupArn,
          Targets: instanceIds.map((id) => ({ Id: id })),
        }),
      );

      console.log(
        `Registered ${instanceIds.length} instances with target group`,
      );
    } else {
      console.log('No instances found in the Auto Scaling group');
    }

    return {
      Status: 'SUCCESS',
      PhysicalResourceId: `${autoScalingGroupName}-${targetGroupArn}`,
    };
  } catch (error) {
    console.error('Error registering targets:', error as Error);
    return {
      Status: 'FAILED',
      Reason: `Error: ${
        error instanceof Error ? error.message : String(error)
      }`,
      PhysicalResourceId: event.LogicalResourceId,
    };
  }
};
