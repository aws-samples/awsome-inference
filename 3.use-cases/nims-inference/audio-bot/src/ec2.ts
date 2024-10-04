import { Stack, Fn, CustomResource } from 'aws-cdk-lib';

import { CfnAutoScalingGroup } from 'aws-cdk-lib/aws-autoscaling';
import { Certificate } from 'aws-cdk-lib/aws-certificatemanager';
import {
  InstanceType,
  MachineImage,
  Peer,
  Port,
  SecurityGroup,
  SubnetType,
  UserData,
  InstanceClass,
  InstanceSize,
  IVpc,
  OperatingSystemType,
  CfnLaunchTemplate,
} from 'aws-cdk-lib/aws-ec2';
import {
  ApplicationLoadBalancer,
  ApplicationProtocol,
  ApplicationProtocolVersion,
  ApplicationTargetGroup,
  ListenerCertificate,
  Protocol,
  TargetType,
} from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import {
  ManagedPolicy,
  Role,
  ServicePrincipal,
  PolicyStatement,
  Effect,
  InstanceProfile,
} from 'aws-cdk-lib/aws-iam';
import { RetentionDays } from 'aws-cdk-lib/aws-logs';
import { ARecord, IHostedZone, RecordTarget } from 'aws-cdk-lib/aws-route53';
import { LoadBalancerTarget } from 'aws-cdk-lib/aws-route53-targets';
import { Provider } from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';
import { RegisterTargetsFunction } from './lambda';

interface EC2ResourcesProps {
  vpc: IVpc;
  nimCertificate: Certificate;
  hostedZone: IHostedZone;
  nimHostName: string;
  domainName: string;
  capacityReservationId: string;
  vendorName: string;
  containerName: string;
  containerTag: string;
}

export class EC2Resources extends Construct {
  public readonly autoScalingGroup: CfnAutoScalingGroup;
  public readonly targetGroup: ApplicationTargetGroup;
  public readonly sttTargetGroup: ApplicationTargetGroup;
  public readonly ttsTargetGroup: ApplicationTargetGroup;

  constructor(scope: Construct, id: string, props: EC2ResourcesProps) {
    super(scope, id);

    // Create IAM Role
    const ec2Role = new Role(this, 'EC2Role', {
      assumedBy: new ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Add permission to access the specific secret
    ec2Role.addToPolicy(
      new PolicyStatement({
        effect: Effect.ALLOW,
        actions: ['secretsmanager:GetSecretValue'],
        resources: [
          `arn:aws:secretsmanager:${Stack.of(this).region}:${
            Stack.of(this).account
          }:secret:NGC_API_KEY-*`,
        ],
      }),
    );

    const instanceProfile = new InstanceProfile(this, 'EC2InstanceProfile', {
      role: ec2Role,
    });

    // Create Security Group for EC2
    const ec2SecurityGroup = new SecurityGroup(this, 'EC2SecurityGroup', {
      vpc: props.vpc,
      allowAllOutbound: true,
      description: 'Security group for EC2 instance',
    });

    // Add SSH access to the security group
    ec2SecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(22),
      'Allow SSH access',
    );

    // Create ALB Security Group
    const albSecurityGroup = new SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: props.vpc,
      allowAllOutbound: true,
      description: 'Security group for ALB',
    });

    albSecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(80),
      'Allow HTTP traffic',
    );
    albSecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(443),
      'Allow HTTPS traffic',
    );

    albSecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(50051),
      'Allow gRPC traffic for Speech-to-Text (STT)',
    );
    albSecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(50052),
      'Allow gRPC traffic for Text-to-Speech (TTS)',
    );

    albSecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(9000),
      'Allow HTTP traffic for STT',
    );

    albSecurityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(9001),
      'Allow HTTP traffic for TTS',
    );
    // Allow traffic from ALB to EC2 using connections
    ec2SecurityGroup.connections.allowFrom(albSecurityGroup, Port.tcp(8000));
    ec2SecurityGroup.connections.allowFrom(albSecurityGroup, Port.tcp(9000));
    ec2SecurityGroup.connections.allowFrom(albSecurityGroup, Port.tcp(9001));
    ec2SecurityGroup.connections.allowFrom(albSecurityGroup, Port.tcp(50051));
    ec2SecurityGroup.connections.allowFrom(albSecurityGroup, Port.tcp(50052));

    const userData = UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      '',
      '# Enable exit on error and enable command printing for debugging',
      'set -ex',
      '',
      '# Function to log messages',
      'log_message() {',
      '    echo "$(date \'+%Y-%m-%d %H:%M:%S\') - $1" | tee -a /var/log/user-data.log',
      '}',
      '',
      'log_message "Starting user-data script execution"',
      '',
      '# Update and install dependencies',
      'log_message "Updating package lists and installing dependencies"',
      'apt-get update',
      'apt-get install -y gcc unzip python3-pip',
      '',
      '# Install AWS CLI',
      'log_message "Installing AWS CLI"',
      'curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"',
      'unzip awscliv2.zip',
      './aws/install',
      '',
      '# Install NVIDIA drivers and CUDA toolkit',
      'log_message "Installing NVIDIA drivers and CUDA toolkit"',
      'wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb',
      'dpkg -i cuda-keyring_1.1-1_all.deb',
      'apt-get update',
      'apt-get install -y cuda-toolkit-12-6 nvidia-open',
      '',
      '# Install Docker',
      'log_message "Installing Docker"',
      'apt-get install -y apt-transport-https ca-certificates curl software-properties-common',
      'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -',
      'add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"',
      'apt-get update',
      'apt-get install -y docker-ce docker-ce-cli containerd.io',
      '',
      '# Install NVIDIA Container Toolkit',
      'log_message "Installing NVIDIA Container Toolkit"',
      'curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg',
      'curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \\',
      "    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \\",
      '    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list',
      'apt-get update',
      'apt-get install -y nvidia-container-toolkit',
      'apt-get install cuda-drivers-fabricmanager-560 -y',
      'systemctl enable nvidia-fabricmanager',
      'systemctl start nvidia-fabricmanager',
      '',
      '# Configure Docker to use NVIDIA runtime',
      'log_message "Configuring Docker to use NVIDIA runtime"',
      'nvidia-ctk runtime configure --runtime=docker',
      'systemctl restart docker',
      '',
      '# Retrieve NGC API Key from Secrets Manager',
      'log_message "Retrieving NGC API Key from Secrets Manager"',
      `NGC_API_KEY=$(aws secretsmanager get-secret-value --secret-id NGC_API_KEY --query SecretString --output text --region ${
        Stack.of(this).region
      })`,
      '',
      '# Create cache directory',
      'log_message "Creating cache directory"',
      'mkdir -p /home/ubuntu/.cache/nim',
      'chown ubuntu:ubuntu /home/ubuntu/.cache/nim',
      '',
      '# Login to NGC',
      'log_message "Logging in to NGC"',
      "echo $NGC_API_KEY | docker login nvcr.io -u '$oauthtoken' --password-stdin",
      '',
      '# Run the NIM container',
      'log_message "Running the NIM container"',
      `docker run -d --restart unless-stopped --name=${props.containerName} \\`,
      '  --runtime=nvidia \\',
      '  --gpus \'"device=0,1,2,3"\' \\',
      '  -e NGC_API_KEY=$NGC_API_KEY \\',
      '  -e NIM_MODEL_PROFILE=tensorrt_llm-h100-fp8-tp2-latency \\',
      '  -v "/home/ubuntu/.cache/nim:/opt/nim/.cache" \\',
      '  -u $(id -u ubuntu) \\',
      '  -p 8000:8000 \\',
      `  nvcr.io/nim/${props.vendorName}/${props.containerName}:${props.containerTag}`,
      '',
      '# Run the ASR container',
      'log_message "Running the ASR container"',
      'export CONTAINER_NAME_ASR=parakeet-ctc-1.1b-asr',
      'docker run -d --restart unless-stopped --name=$CONTAINER_NAME_ASR \\',
      '  --runtime=nvidia \\',
      '  --gpus \'"device=6"\' \\',
      '  -e NGC_API_KEY=$NGC_API_KEY \\',
      '  -e NIM_MANIFEST_PROFILE=7f0287aa-35d0-11ef-9bba-57fc54315ba3 \\',
      '  -e NIM_HTTP_API_PORT=9000 \\',
      '  -e NIM_GRPC_API_PORT=50051 \\',
      '  -p 9000:9000 \\',
      '  -p 50051:50051 \\',
      '  nvcr.io/nim/nvidia/parakeet-ctc-1.1b-asr:1.0.0',
      '',
      '# Run the TTS container',
      'log_message "Running the TTS container"',
      'export CONTAINER_NAME_TTS=fastpitch-hifigan-tts',
      'docker run -d --restart unless-stopped --name=$CONTAINER_NAME_TTS \\',
      '  --runtime=nvidia \\',
      '  --gpus \'"device=7"\' \\',
      '  --shm-size=8GB \\',
      '  -e NGC_API_KEY=$NGC_API_KEY \\',
      '  -e NIM_MANIFEST_PROFILE=bbce2a3a-4337-11ef-84fe-e7f5af9cc9af \\',
      '  -e NIM_HTTP_API_PORT=9001 \\',
      '  -e NIM_GRPC_API_PORT=50052 \\',
      '  -p 9001:9001 \\',
      '  -p 50052:50052 \\',
      '  nvcr.io/nim/nvidia/fastpitch-hifigan-tts:1.0.0',
      '',
      'log_message "User-data script execution completed"',
    );

    const launchTemplate = new CfnLaunchTemplate(
      this,
      'InstanceLaunchTemplate',
      {
        launchTemplateData: {
          imageId: MachineImage.fromSsmParameter(
            '/aws/service/canonical/ubuntu/server/jammy/stable/current/amd64/hvm/ebs-gp2/ami-id',
            { os: OperatingSystemType.LINUX },
          ).getImage(this).imageId,
          instanceType: InstanceType.of(
            InstanceClass.P5,
            InstanceSize.XLARGE48,
          ).toString(),
          userData: Fn.base64(userData.render()),
          iamInstanceProfile: { arn: instanceProfile.instanceProfileArn },
          securityGroupIds: [ec2SecurityGroup.securityGroupId],
          instanceMarketOptions: { marketType: 'capacity-block' },
          metadataOptions: {
            httpTokens: 'required',
            httpPutResponseHopLimit: 2,
          },
          capacityReservationSpecification: {
            capacityReservationTarget: {
              capacityReservationId: props.capacityReservationId,
            },
          },
          blockDeviceMappings: [
            {
              deviceName: '/dev/sda1',
              ebs: {
                volumeSize: 1000,
                volumeType: 'gp3',
              },
            },
          ],
        },
        launchTemplateName: 'NIMInstanceLaunchTemplate',
      },
    );

    this.autoScalingGroup = new CfnAutoScalingGroup(this, 'AutoScalingGroup', {
      vpcZoneIdentifier: [props.vpc.publicSubnets[0].subnetId],
      desiredCapacity: '1',
      minSize: '1',
      maxSize: '1',
      launchTemplate: {
        launchTemplateId: launchTemplate.ref,
        version: launchTemplate.attrLatestVersionNumber,
      },
    });

    this.targetGroup = new ApplicationTargetGroup(this, 'EC2TargetGroup', {
      vpc: props.vpc,
      port: 8000,
      protocol: ApplicationProtocol.HTTP,
      targetType: TargetType.INSTANCE,
      healthCheck: {
        path: '/v1/health/ready',
        protocol: Protocol.HTTP,
        port: '8000',
      },
    });

    this.sttTargetGroup = new ApplicationTargetGroup(this, 'STTTargetGroup', {
      vpc: props.vpc,
      port: 50051,
      protocol: ApplicationProtocol.HTTP,
      protocolVersion: ApplicationProtocolVersion.GRPC,
      targetType: TargetType.INSTANCE,
      healthCheck: {
        path: '/',
        protocol: Protocol.HTTP,
      },
    });

    // Create gRPC target group for Text-to-Speech (TTS)
    this.ttsTargetGroup = new ApplicationTargetGroup(this, 'TTSTargetGroup', {
      vpc: props.vpc,
      port: 50052,
      protocol: ApplicationProtocol.HTTP,
      protocolVersion: ApplicationProtocolVersion.GRPC,
      targetType: TargetType.INSTANCE,
      healthCheck: {
        path: '/',
        protocol: Protocol.HTTP,
      },
    });

    // Create ALB
    const alb = new ApplicationLoadBalancer(this, 'ALB', {
      vpc: props.vpc,
      vpcSubnets: { subnetType: SubnetType.PUBLIC },
      internetFacing: true,
      securityGroup: albSecurityGroup,
    });

    // Add ALB Listener for HTTPS
    alb.addListener('LLMListener', {
      port: 443,
      protocol: ApplicationProtocol.HTTPS,
      certificates: [
        ListenerCertificate.fromCertificateManager(props.nimCertificate),
      ],
      defaultTargetGroups: [this.targetGroup],
    });

    alb.addListener('STTListenerGRPC', {
      port: 50051,
      protocol: ApplicationProtocol.HTTPS,
      certificates: [
        ListenerCertificate.fromCertificateManager(props.nimCertificate),
      ],
      defaultTargetGroups: [this.sttTargetGroup],
    });

    alb.addListener('STTListenerHTTP', {
      port: 9000,
      protocol: ApplicationProtocol.HTTPS,
      certificates: [
        ListenerCertificate.fromCertificateManager(props.nimCertificate),
      ],
      defaultTargetGroups: [this.sttTargetGroup],
    });

    // Add gRPC Listener for Text-to-Speech (TTS)
    alb.addListener('TTSListenerGRPC', {
      port: 50052,
      protocol: ApplicationProtocol.HTTPS,
      certificates: [
        ListenerCertificate.fromCertificateManager(props.nimCertificate),
      ],
      defaultTargetGroups: [this.ttsTargetGroup],
    });

    alb.addListener('TTSListenerHTTP', {
      port: 9001,
      protocol: ApplicationProtocol.HTTPS,
      certificates: [
        ListenerCertificate.fromCertificateManager(props.nimCertificate),
      ],
      defaultTargetGroups: [this.ttsTargetGroup],
    });

    // HTTP to HTTPS redirect
    alb.addRedirect({
      sourceProtocol: ApplicationProtocol.HTTP,
      sourcePort: 80,
      targetProtocol: ApplicationProtocol.HTTPS,
      targetPort: 443,
    });

    // Create DNS record
    new ARecord(this, 'DNSRecord', {
      zone: props.hostedZone,
      recordName: `${props.nimHostName}.${props.domainName}`,
      target: RecordTarget.fromAlias(new LoadBalancerTarget(alb)),
    });

    // Create Lambda function to register targets
    const registerTargetsFunction = new RegisterTargetsFunction(
      this,
      'RegisterTargetsFunction',
    );

    registerTargetsFunction.lambdaFunction.addToRolePolicy(
      new PolicyStatement({
        effect: Effect.ALLOW,
        actions: [
          'elasticloadbalancing:RegisterTargets',
          'elasticloadbalancing:DeregisterTargets',
        ],
        resources: [
          this.targetGroup.targetGroupArn,
          this.sttTargetGroup.targetGroupArn,
          this.ttsTargetGroup.targetGroupArn,
        ],
      }),
    );

    const provider = new Provider(this, 'Provider', {
      onEventHandler: registerTargetsFunction.lambdaFunction,
      logRetention: RetentionDays.ONE_WEEK,
    });

    // Create Custom Resource for the main target group
    new CustomResource(this, 'RegisterMainTargetCustomResource', {
      serviceToken: provider.serviceToken,
      properties: {
        AutoScalingGroupName: this.autoScalingGroup.ref,
        TargetGroupArn: this.targetGroup.targetGroupArn,
      },
    });

    // Create Custom Resource for the STT target group
    new CustomResource(this, 'RegisterSTTTargetCustomResource', {
      serviceToken: provider.serviceToken,
      properties: {
        AutoScalingGroupName: this.autoScalingGroup.ref,
        TargetGroupArn: this.sttTargetGroup.targetGroupArn,
      },
    });

    // Create Custom Resource for the TTS target group
    new CustomResource(this, 'RegisterTTSTargetCustomResource', {
      serviceToken: provider.serviceToken,
      properties: {
        AutoScalingGroupName: this.autoScalingGroup.ref,
        TargetGroupArn: this.ttsTargetGroup.targetGroupArn,
      },
    });
  }
}
