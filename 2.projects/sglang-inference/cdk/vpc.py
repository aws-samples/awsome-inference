from aws_cdk import aws_ec2 as ec2
from constructs import Construct

class Vpc(Construct):
    """Creates a VPC with public and private subnets for the SGLang inference cluster.
    
    The VPC is configured with:
    - Public subnets for the router node to accept external requests
    - Private subnets for worker nodes to run inference securely
    - NAT Gateway to allow worker nodes to download models and updates
    - Spread across 2 AZs for high availability
    """

    def __init__(self, scope: Construct, construct_id: str) -> None:
        super().__init__(scope, construct_id)

        self.vpc = ec2.Vpc(self, "VPC",
            max_azs=2,  # Use 2 Availability Zones for high availability
            nat_gateways=1,  # Single NAT Gateway to minimize costs while enabling internet access
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24  # /24 CIDR block allowing 256 IPs per subnet
                ),
                ec2.SubnetConfiguration(
                    name="Private", 
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_NAT,
                    cidr_mask=24  # /24 CIDR block allowing 256 IPs per subnet
                )
            ]
        )