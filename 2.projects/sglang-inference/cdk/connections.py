from aws_cdk import aws_ec2 as ec2
from constructs import Construct
from .workers import Workers
from .router import Router

class NetworkConnections(Construct):
    """Configure security group rules between SGLang router and worker nodes.
    
    This construct sets up bidirectional network connectivity between the router
    and worker nodes to enable request routing and worker registration coordination.
    The router needs to forward inference requests to workers, while workers need
    to communicate coming online to the router.
    """

    def __init__(self, scope: Construct, construct_id: str, workers: Workers, router: Router) -> None:
        super().__init__(scope, construct_id)
        
        # Allow router to forward inference requests to workers
        workers.asg.connections.allow_from(
            router.security_group,
            ec2.Port.tcp(7999),  # Worker API port
            "Allow inference traffic from router to workers"
        )
        
        # Allow workers to send cache updates to router
        router.security_group.connections.allow_from(
            workers.asg.connections.security_groups[0],
            ec2.Port.tcp(8000),  # Router API port
            "Allow cache coordination traffic from workers to router"
        )