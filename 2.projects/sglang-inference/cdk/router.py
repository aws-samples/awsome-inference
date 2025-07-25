from aws_cdk import (
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3_assets as assets,
)
from constructs import Construct

class Router(Construct):
    """Creates an EC2 instance to run the SGLang router service.
    
    The router coordinates distributed inference across worker nodes by:
    - Managing worker node registration and health checks
    - Routing inference requests to available workers
    - Maintaining a distributed prompt cache across the worker fleet
    - Exposing a public API endpoint for client requests
    """

    def __init__(self, scope: Construct, construct_id: str, vpc, logs, router_ip="10.0.0.100") -> None:
        super().__init__(scope, construct_id)
                
        # Create security group for router instance with public access
        self.security_group = ec2.SecurityGroup(self, "RouterSecurityGroup",
            vpc=vpc.vpc,
            description="Security group for SGLang router instance",
            allow_all_outbound=True
        )
        
        # Create IAM role with permissions for router operations
        router_role = iam.Role(self, "RouterEC2Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com")
        )
        # Add required managed policies
        router_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
        )
        router_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )
        # Add permissions to discover worker instances
        router_role.add_to_policy(iam.PolicyStatement(
            actions=[
                "ec2:DescribeInstances",
                "autoscaling:DescribeAutoScalingGroups",
            ],
            resources=["*"]
        ))

        # Upload router application code to S3
        script_asset = assets.Asset(self, "RouterScriptAsset",
            path="./src/run_router.py"
        )
        script_asset.grant_read(router_role)
                        
        # Configure user data script to set up and run router service
        router_user_data = ec2.UserData.for_linux()
        router_user_data.add_commands(
            # Install dependencies
            'apt install -y python3 python3-pip',
            
            # Configure CloudWatch monitoring
            f'aws s3 cp s3://{logs.cloudwatch_agent_asset.s3_bucket_name}/{logs.cloudwatch_agent_asset.s3_object_key} /opt/aws/amazon-cloudwatch-agent/bin/config.json',
            'sudo amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s',
            
            # Install SGLang router package
            'pip install sglang-router',
            
            # Set up application directory and code
            'sudo mkdir -p /opt/app',
            f'aws s3 cp s3://{script_asset.s3_bucket_name}/{script_asset.s3_object_key} /opt/app/run_router.py',
            'sudo chmod +x /opt/app/run_router.py',
            
            # Start router service on port 8000
            'python3 /opt/app/run_router.py --host 0.0.0.0 --port 8000',
        )
        
        # Launch router EC2 instance
        router_instance = ec2.Instance(self, "RouterInstance",
            vpc=vpc.vpc,
            instance_type=ec2.InstanceType("r7i.xlarge"),
            machine_image=ec2.MachineImage.lookup(
                name="Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*",
                owners=["amazon"]
            ),
            role=router_role,
            user_data=router_user_data,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            private_ip_address=router_ip,
            security_group=self.security_group
        )
        
        # Allow inbound traffic to router API port
        router_instance.connections.allow_from_any_ipv4(
            ec2.Port.tcp(8000),
            "Allow public access to router API endpoint"
        )