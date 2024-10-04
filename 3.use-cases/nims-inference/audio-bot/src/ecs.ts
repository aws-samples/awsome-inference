import { Stack } from 'aws-cdk-lib';
import { Certificate } from 'aws-cdk-lib/aws-certificatemanager';
import { SecurityGroup, Port, SubnetType, Vpc } from 'aws-cdk-lib/aws-ec2';
import {
  AwsLogDriver,
  Cluster,
  ContainerImage,
  FargateTaskDefinition,
  FargateService,
  Secret as EcsSecret,
} from 'aws-cdk-lib/aws-ecs';
import {
  ApplicationLoadBalancer,
  ApplicationProtocol,
  ApplicationTargetGroup,
  ListenerCertificate,
  Protocol,
} from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import {
  Role,
  ServicePrincipal,
  PolicyStatement,
  Effect,
} from 'aws-cdk-lib/aws-iam';
import { ARecord, IHostedZone, RecordTarget } from 'aws-cdk-lib/aws-route53';
import { LoadBalancerTarget } from 'aws-cdk-lib/aws-route53-targets';
import { Secret } from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

interface ECSResourcesProps {
  vpc: Vpc;
  logLevel: string;
  loadBalancerSecurityGroup: SecurityGroup;
  twilioCertificate: Certificate;
  hostedZone: IHostedZone;
  twilioHostName: string;
  domainName: string;
}

export class ECSResources extends Construct {
  fargateService: FargateService;
  applicationLoadBalancer: ApplicationLoadBalancer;

  constructor(scope: Construct, id: string, props: ECSResourcesProps) {
    super(scope, id);

    const twilioServerRole = new Role(this, 'twilioServerRole', {
      assumedBy: new ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    const twilioAuthToken = Secret.fromSecretPartialArn(
      this,
      'TwilioAuthToken',
      `arn:aws:secretsmanager:${Stack.of(this).region}:${
        Stack.of(this).account
      }:secret:TWILIO_AUTH_TOKEN`,
    );

    const secretArns = [twilioAuthToken.secretArn];

    // Create a custom policy for reading specific secrets
    const secretsPolicy = new PolicyStatement({
      effect: Effect.ALLOW,
      actions: ['secretsmanager:GetSecretValue'],
      resources: secretArns,
    });

    twilioServerRole.addToPolicy(secretsPolicy);

    this.applicationLoadBalancer = new ApplicationLoadBalancer(
      this,
      'applicationLoadBalancer',
      {
        vpc: props.vpc,
        vpcSubnets: { subnetType: SubnetType.PUBLIC },
        internetFacing: true,
        securityGroup: props.loadBalancerSecurityGroup,
      },
    );

    // Add HTTP to HTTPS redirect
    this.applicationLoadBalancer.addRedirect({
      sourceProtocol: ApplicationProtocol.HTTP,
      sourcePort: 80,
      targetProtocol: ApplicationProtocol.HTTPS,
      targetPort: 443,
    });

    const cluster = new Cluster(this, 'cluster', {
      vpc: props.vpc,
    });

    const taskDefinition = new FargateTaskDefinition(this, 'taskDefinition', {
      taskRole: twilioServerRole,
      cpu: 2048,
      memoryLimitMiB: 4096,
    });

    const fargateSecurityGroup = new SecurityGroup(
      this,
      'webSocketServiceSecurityGroup',
      { vpc: props.vpc, allowAllOutbound: true },
    );

    this.fargateService = new FargateService(this, 'TwilioService', {
      cluster: cluster,
      taskDefinition: taskDefinition,
      assignPublicIp: true,
      desiredCount: 1,
      vpcSubnets: { subnetType: SubnetType.PUBLIC },
      securityGroups: [fargateSecurityGroup],
    });

    taskDefinition.addContainer('twilioServer', {
      image: ContainerImage.fromAsset('src/resources/twilioServer'),
      environment: {
        LOG_LEVEL: props.logLevel,
        RIVA_TTS_SERVICE_ADDRESS: `nim.${props.domainName}:50052`,
        RIVA_ASR_SERVICE_ADDRESS: `nim.${props.domainName}:50051`,
        NIM_LLM_SERVICE_ADDRESS: `nim.${props.domainName}`,
      },
      secrets: {
        TWILIO_AUTH_TOKEN: EcsSecret.fromSecretsManager(twilioAuthToken),
      },
      memoryLimitMiB: 4096,
      cpu: 2048,
      portMappings: [{ containerPort: 80, hostPort: 80 }],
      logging: new AwsLogDriver({ streamPrefix: 'TwilioServer' }),
    });

    fargateSecurityGroup.connections.allowFrom(
      props.loadBalancerSecurityGroup,
      Port.tcp(443),
    );

    const twilioServerTargetGroup = new ApplicationTargetGroup(
      this,
      'twilioServerTargetGroup',
      {
        vpc: props.vpc,
        port: 443,
        protocol: ApplicationProtocol.HTTP,
        targets: [
          this.fargateService.loadBalancerTarget({
            containerName: 'twilioServer',
            containerPort: 80,
          }),
        ],
        healthCheck: {
          path: '/health',
          protocol: Protocol.HTTP,
          port: '80',
        },
      },
    );

    this.applicationLoadBalancer.addListener('twilioListener', {
      port: 443,
      protocol: ApplicationProtocol.HTTPS,
      certificates: [
        ListenerCertificate.fromCertificateManager(props.twilioCertificate),
      ],
      defaultTargetGroups: [twilioServerTargetGroup],
    });

    new ARecord(this, 'twilioServer', {
      zone: props.hostedZone,
      recordName: props.twilioHostName,
      target: RecordTarget.fromAlias(
        new LoadBalancerTarget(this.applicationLoadBalancer),
      ),
    });
  }
}
