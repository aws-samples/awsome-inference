import {
  Peer,
  Port,
  SecurityGroup,
  SubnetType,
  Vpc,
} from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';

export class VPCResources extends Construct {
  public loadBalancerSecurityGroup: SecurityGroup;
  public vpc: Vpc;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    this.vpc = new Vpc(this, 'VPC', {
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'PublicSubnet',
          subnetType: SubnetType.PUBLIC,
        },
      ],
      maxAzs: 3,
      natGateways: 0,
    });

    this.loadBalancerSecurityGroup = new SecurityGroup(
      this,
      'applicationLoadBalancerSecurityGroup',
      {
        vpc: this.vpc,
        description: 'Security Group for ALB',
      },
    );

    this.loadBalancerSecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(8765),
    );
  }
}
