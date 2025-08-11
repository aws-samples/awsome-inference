from aws_cdk import (
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3_assets as assets,
    aws_imagebuilder as imagebuilder,
)
from constructs import Construct
from .logs import Logs

class ImageBuilder(Construct):
    """Creates an AMI with Image Builder to bootstrap worker nodes quickly.
    
    This construct:
    - Sets up IAM roles and instance profile for Image Builder
    - Creates a security group for the build instance
    - Configures infrastructure settings like instance type and networking
    - Defines build components to install Python, PyTorch, SGLang and application code
    - Builds an AMI that can be used to quickly launch worker nodes
    """

    def __init__(self, scope: Construct, construct_id: str, vpc, logs: Logs, hf_model_id: str, instance_type: str = "g6e.xlarge") -> None:
        super().__init__(scope, construct_id)

        # Model configuration
        self.hf_model_id = hf_model_id
        self.model_name = hf_model_id.split("/")[-1]

        # Create IAM role with permissions needed for Image Builder and EC2
        imagebuilder_role = iam.Role(self, "ImageBuilderRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("imagebuilder.amazonaws.com"),
                iam.ServicePrincipal("ec2.amazonaws.com")
            )
        )
        imagebuilder_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
        )
        imagebuilder_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("EC2InstanceProfileForImageBuilder")
        )
        
        # Create instance profile that will be used by the build instance
        instance_profile = iam.CfnInstanceProfile(self, "InstanceProfileImageBuilder",
            instance_profile_name=f"InstanceProfileImageBuilder-{scope.node.id}",
            roles=[imagebuilder_role.role_name]
        )

        # Security group allowing outbound internet access for package installation
        security_group = ec2.SecurityGroup(self, "ImageBuilderSG",
            vpc=vpc.vpc,
            description="Security group for Image Builder",
            allow_all_outbound=True
        )
    
        # Configure the build infrastructure settings
        infra_config = imagebuilder.CfnInfrastructureConfiguration(self, "InfraConfig",
            name=f"ImageBuilderInfraConfig-{scope.node.id}",
            instance_profile_name=instance_profile.instance_profile_name,
            instance_types=[instance_type], # GPU instance type
            subnet_id=vpc.vpc.public_subnets[0].subnet_id,
            security_group_ids=[security_group.security_group_id],
            instance_metadata_options={
                "httpTokens": "required",
            }
        )
        infra_config.node.add_dependency(instance_profile)
        
        # Upload application code and config files to S3 for Image Builder to access
        script_asset = assets.Asset(self, "ScriptAsset",
            path="./src/run_worker.py"
        )
        script_asset.grant_read(imagebuilder_role)
        
        monitor_logs_asset = assets.Asset(self, "MonitorLogsAsset",
            path="./src/monitor_logs.py"
        )
        monitor_logs_asset.grant_read(imagebuilder_role)
        
        cloudwatch_agent_asset = logs.cloudwatch_agent_asset
        cloudwatch_agent_asset.grant_read(imagebuilder_role)
        
        # Define build steps to install dependencies and application code
        install_component = imagebuilder.CfnComponent(self, "InstallComponent",
            name=f"InstallDependencies-{scope.node.id}",
            platform="Linux",
            version="1.0.0",
            data=f"""
            name: InstallDependencies
            description: Install Python, PyTorch, SGLang and application dependencies
            schemaVersion: 1.0
            phases:
              - name: build
                steps:
                  - name: InstallPythonDeps
                    action: ExecuteBash
                    inputs:
                      commands:
                        - mkdir -p /opt/sglang/logs
                        # Install system packages
                        - apt update
                        - DEBIAN_FRONTEND=noninteractive apt install -y ninja-build python3-venv
                        # Create virtual environment
                        - python3 -m venv /opt/sglang/venv
                        # Upgrade pip in venv
                        - /opt/sglang/venv/bin/pip install --upgrade pip
                        # Install basic dependencies
                        - /opt/sglang/venv/bin/pip install nixl huggingface-hub
                        # Clone sglang main branch and install
                        - git clone https://github.com/sgl-project/sglang.git /opt/sglang/source
                        - cd /opt/sglang/source && /opt/sglang/venv/bin/pip install -e "python[all]"
                        # Install vllm for awq_marlin quantization support
                        # Remove vllm for the time being to avoid conflicts with newest build of sglang /opt/sglang/venv/bin/pip install vllm==0.9.0.1
                        # Download model from Hugging Face and create a model directory
                        - mkdir -p /opt/sglang/models/{self.model_name}
                        - /opt/sglang/venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='{self.hf_model_id}', revision='main', local_dir='/opt/sglang/models/{self.model_name}')"
                        # Prep cache for torch compile
                        - mkdir -p /opt/sglang/torch_compile_cache/
                        - export TORCHINDUCTOR_CACHE_DIR=/opt/sglang/torch_compile_cache/
                        # Copy application files
                        - aws s3 cp s3://{cloudwatch_agent_asset.s3_bucket_name}/{cloudwatch_agent_asset.s3_object_key} /opt/aws/amazon-cloudwatch-agent/bin/config.json
                        - mkdir -p /opt/app
                        - aws s3 cp s3://{script_asset.s3_bucket_name}/{script_asset.s3_object_key} /opt/app/run_worker.py
                        - chmod +x /opt/app/run_worker.py
                        - aws s3 cp s3://{monitor_logs_asset.s3_bucket_name}/{monitor_logs_asset.s3_object_key} /opt/app/monitor_logs.py
                        - chmod +x /opt/app/monitor_logs.py
            """
        )

        # Configure the AMI recipe with base image and storage
        recipe = imagebuilder.CfnImageRecipe(self, "ImageRecipe",
            name=f"SGLangImageRecipe-{scope.node.id}",
            version="1.0.0",
            components=[{
                "componentArn": install_component.attr_arn
            }],
            parent_image=ec2.MachineImage.lookup(
                name="Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 24.04) 20250722",
                owners=["amazon"]
            ).get_image(self).image_id,
            block_device_mappings=[{
                "deviceName": "/dev/sda1",
                "ebs": {
                    "volumeSize": 300,
                    "volumeType": "io2",
                    "iops": 10000,
                    "deleteOnTermination": True
                }
            }]
        )

        # Create the image
        self.image = imagebuilder.CfnImage(self, "Image",
            image_recipe_arn=recipe.attr_arn,
            infrastructure_configuration_arn=infra_config.attr_arn,
            image_tests_configuration={
                "imageTestsEnabled": False,
                "timeoutMinutes": 60
            },
            tags={
                "Name": f"sglang-image-{scope.node.id}",
                "CreatedBy": "ImageBuilder",
                "Stack": scope.node.id
            },
        )