from aws_cdk import (
    aws_autoscaling as autoscaling,
    aws_ec2 as ec2,
    aws_iam as iam,
    Stack,
    Duration,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
)
from constructs import Construct
from .image_builder import ImageBuilder

from aws_cdk.aws_autoscaling import CfnScalingPolicy as ScalingPolicy
from aws_cdk.aws_autoscaling import CfnScalingPolicy

# Shorter aliases for nested classes
MetricDim = CfnScalingPolicy.MetricDimensionProperty
Metric = CfnScalingPolicy.MetricProperty
MetricStat = CfnScalingPolicy.TargetTrackingMetricStatProperty
MetricQuery = CfnScalingPolicy.TargetTrackingMetricDataQueryProperty
MetricSpec = CfnScalingPolicy.CustomizedMetricSpecificationProperty
TrackingConfig = CfnScalingPolicy.TargetTrackingConfigurationProperty

class Workers(Construct):
    """Creates an Auto Scaling Group of GPU worker nodes for distributed ML inference.
    
    This construct:
    - Configures worker nodes to run SGLang inference workers
    - Sets up CloudWatch monitoring and logging
    - Implements warm pooling for faster scaling
    - Configures auto-scaling based on inference load
    - Handles graceful worker deregistration during scale-in
    """
    def __init__(self, scope: Construct, construct_id: str, vpc: ec2.Vpc, image_builder: ImageBuilder, instance_type: str = "g6e.xlarge", extra_args: str = "", router_ip: str = "10.0.0.100") -> None:
        super().__init__(scope, construct_id)
        
        # Create IAM role for worker instances
        role = iam.Role(self, "WorkerEC2Role", 
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com")
        )
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
        )
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )
        role.add_to_policy(iam.PolicyStatement(
            actions=[
                "ec2:DescribeInstances",
                "autoscaling:DescribeAutoScalingGroups",
            ],
            resources=["*"]
        ))
        
        # Configure user data first
        user_data = ec2.MultipartUserData()
        
        # Ensure cloud-init runs user scripts on every boot
        cloud_config = ec2.UserData.for_linux()
        cloud_config.add_commands(
            "#cloud-config",
            "cloud_final_modules:",
            "- [scripts-user, always]"
        )
        user_data.add_part(ec2.MultipartBody.from_user_data(
            cloud_config,
            "text/cloud-config; charset=\"us-ascii\""
        ))
                
        # Configure worker startup script
        script_commands = ec2.UserData.for_linux() 
        script_commands.add_commands(
            # Start CloudWatch monitoring
            'sudo amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s',
            'python3 /opt/app/monitor_logs.py &',
            
            # Check if instance is in warm pool before starting worker
            'TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` && curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/autoscaling/target-lifecycle-state >> /opt/sglang/logs/sglang.log',
            'LIFECYCLE_STATE=`cat /opt/sglang/logs/sglang.log | tail -n 1`',
            'if [ "$LIFECYCLE_STATE" = "Warmed:Stopped" ]; then',
            '  echo "Instance in Warmed:Stopped state, not starting worker" >> /opt/sglang/logs/sglang.log',
            'else',
            # Start SGLang worker and connect to router with extra args
            '  export TORCHINDUCTOR_CACHE_DIR=/opt/sglang/torch_compile_cache/',
            '  export PYTHONPATH=/opt/sglang/source:$PYTHONPATH',
            f'  python3 /opt/app/run_worker.py --gpu-id 0 --model /opt/sglang/models/{image_builder.model_name} --router-url http://{router_ip}:8000 {extra_args}',
            'fi'
        )
        user_data.add_part(ec2.MultipartBody.from_user_data(
            script_commands,
            "text/x-shellscript; charset=\"us-ascii\""
        ))
        
        # Create Auto Scaling Group with user data
        self.asg = autoscaling.AutoScalingGroup(self, "ASG",
            vpc=vpc.vpc,
            instance_type=ec2.InstanceType(instance_type),  # GPU instance for ML inference
            machine_image=ec2.MachineImage.generic_linux({Stack.of(self).region: image_builder.image.attr_image_id}),
            role=role,
            min_capacity=1,
            max_capacity=3,
            desired_capacity=1,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            associate_public_ip_address=False,
            group_metrics=[autoscaling.GroupMetrics.all()],
            user_data=user_data,
        )
        
        # Configure warm pool to maintain pre-initialized instances
        self.asg.add_warm_pool(
            max_group_prepared_capacity=1,
            min_size=1,
        )
        
        self.asg.node.add_dependency(image_builder.image)
        
        # Configure auto-scaling based on inference load
        ScalingPolicy(self, "DecodeOpsScalingPolicy",
            auto_scaling_group_name=self.asg.auto_scaling_group_name,
            policy_type="TargetTrackingScaling",
            estimated_instance_warmup=220,
            target_tracking_configuration=TrackingConfig(
                target_value=4,  # Target decode operations per instance
                customized_metric_specification=MetricSpec(
                    metrics=[
                        MetricQuery(
                            id="e1",
                            expression="m1/FILL(m2,REPEAT)",
                            label="Decode operations per instance",
                            period=10,
                            return_data=True,
                        ),
                        MetricQuery(
                            id="m1",
                            metric_stat=MetricStat(
                                metric=Metric(
                                    namespace="SGLang/Workers",
                                    metric_name="NewSequences",
                                    dimensions=[
                                        MetricDim(
                                            name="AutoScalingGroupName",
                                            value="sglang-workers"
                                        )
                                    ]
                                ),
                                stat="Sum",
                                period=10
                            ),
                            return_data=False
                        ),
                        MetricQuery(
                            id="m2", 
                            metric_stat=MetricStat(
                                metric=Metric(
                                    namespace="AWS/AutoScaling",
                                    metric_name="GroupInServiceCapacity",
                                    dimensions=[
                                        MetricDim(
                                            name="AutoScalingGroupName",
                                            value=self.asg.auto_scaling_group_name
                                        )
                                    ]
                                ),
                                stat="Average",
                                period=10
                            ),
                            return_data=False
                        )
                    ]
                )
            ),
        )
        
        # Create Lambda function to deregister workers during scale-in
        lambda_role = iam.Role(self, "DeregisterWorkerLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com")
        )
        lambda_role.add_to_policy(iam.PolicyStatement(
            actions=[
                "logs:CreateLogGroup",
                "logs:CreateLogStream", 
                "logs:PutLogEvents"
            ],
            resources=["*"]
        ))
        lambda_role.add_to_policy(iam.PolicyStatement(
            actions=[
                "ec2:DescribeInstances",
                "ec2:CreateNetworkInterface",
                "ec2:DeleteNetworkInterface", 
                "ec2:DescribeNetworkInterfaces"
            ],
            resources=["*"]
        ))

        deregister_worker_lambda = lambda_.Function(self, "DeregisterWorkerFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            vpc=vpc.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            code=lambda_.Code.from_inline(f"""
import json
import urllib.request
import urllib.error
import boto3

def handler(event, context):
    print('Received event:', json.dumps(event, indent=2))
    
    # Get instance ID and private IP of terminating worker
    instance_id = event['detail']['EC2InstanceId']
    print(f"Instance being terminated: {{instance_id}}")
    
    ec2 = boto3.client('ec2')
    response = ec2.describe_instances(InstanceIds=[instance_id])
    private_ip = response['Reservations'][0]['Instances'][0]['PrivateIpAddress']
    print(f"Private IP of the instance: {{private_ip}}")
    
    # Deregister worker from router
    router_url = "http://{router_ip}:8000"
    worker_url = f"http://{{private_ip}}:7999"
    
    try:
        url = f"{{router_url}}/remove_worker?url={{worker_url}}"
        req = urllib.request.Request(url, method='POST')
        with urllib.request.urlopen(req) as response:
            print(f"Successfully deregistered worker {{worker_url}}")
            return {{
                'statusCode': 200,
                'body': json.dumps('Success')
            }}
    except urllib.error.URLError as e:
        error_msg = str(e.reason) if hasattr(e, 'reason') else str(e)
        print(f"Error deregistering worker: {{error_msg}}")
        return {{
            'statusCode': 500,
            'body': json.dumps(error_msg)
        }}
"""),
            timeout=Duration.seconds(30),
            role=lambda_role
        )

        # Trigger deregistration Lambda on instance termination
        events.Rule(self, "ScaleInRule",
            event_pattern=events.EventPattern(
                source=["aws.autoscaling"],
                detail_type=["EC2 Instance-terminate Lifecycle Action"],
                detail={
                    "AutoScalingGroupName": [self.asg.auto_scaling_group_name]
                }
            ),
            targets=[targets.LambdaFunction(deregister_worker_lambda)]
        )

        # Add lifecycle hook to wait for deregistration
        self.asg.add_lifecycle_hook("ScaleInLifecycleHook",
            lifecycle_transition=autoscaling.LifecycleTransition.INSTANCE_TERMINATING,
            default_result=autoscaling.DefaultResult.CONTINUE,
            heartbeat_timeout=Duration.seconds(300)
        )