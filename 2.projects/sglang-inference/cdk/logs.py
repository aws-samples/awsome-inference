from aws_cdk import (
    aws_logs as logs,
    RemovalPolicy,
    aws_s3_assets as assets,
)
from constructs import Construct

class Logs(Construct):
    """Configure CloudWatch logging for SGLang workers.
    
    This construct:
    - Creates a CloudWatch log group to collect SGLang worker logs
    - Uploads CloudWatch agent config as an S3 asset for worker nodes to access
    - Enables monitoring of worker performance metrics and inference stats
    """

    def __init__(self, scope: Construct, construct_id: str) -> None:
        super().__init__(scope, construct_id)

        # Create CloudWatch log group for worker logs with 1 week retention
        self.log_group = logs.LogGroup(self, "SGLangLogGroup",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Upload CloudWatch agent config to S3 for worker nodes to access
        # This config will be downloaded during instance bootstrap
        self.cloudwatch_agent_asset = assets.Asset(self, "CloudwatchAgentAsset", 
            path="./src/config.json"
        )