import { App, Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { config } from 'dotenv';
import {
  ECSResources,
  VPCResources,
  CertificateResources,
  EC2Resources,
} from '.';
config();

interface NIMVoiceBotProps extends StackProps {
  logLevel: string;
  domainName: string;
  twilioHostName: string;
  nimHostName: string;
  capacityReservationId: string;
  vendorName: string;
  containerName: string;
  containerTag: string;
}

export class NIMVoiceBot extends Stack {
  constructor(scope: Construct, id: string, props: NIMVoiceBotProps) {
    super(scope, id, props);

    if (!props.domainName) {
      throw new Error('Domain Name is required');
    }
    if (!props.twilioHostName) {
      throw new Error('Twilio Host Name is required');
    }
    if (!props.nimHostName) {
      throw new Error('Nim Host Name is required');
    }
    if (!props.capacityReservationId) {
      throw new Error('Capacity Reservation Id is required');
    }

    const certificateResources = new CertificateResources(
      this,
      'CertificateResources',
      {
        domainName: props.domainName,
        twilioHostName: props.twilioHostName,
        nimHostName: props.nimHostName,
      },
    );
    const vpcResources = new VPCResources(this, 'VPCResources');
    new ECSResources(this, 'ECSResources', {
      vpc: vpcResources.vpc,
      loadBalancerSecurityGroup: vpcResources.loadBalancerSecurityGroup,
      logLevel: props.logLevel,
      twilioCertificate: certificateResources.twilioCertificate,
      hostedZone: certificateResources.hostedZone,
      twilioHostName: props.twilioHostName,
      domainName: props.domainName,
    });
    new EC2Resources(this, 'EC2Resources', {
      vpc: vpcResources.vpc,
      nimCertificate: certificateResources.nimCertificate,
      hostedZone: certificateResources.hostedZone,
      nimHostName: props.nimHostName,
      domainName: props.domainName,
      capacityReservationId: props.capacityReservationId,
      vendorName: props.vendorName,
      containerName: props.containerName,
      containerTag: props.containerTag,
    });
  }
}

const devEnv = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: 'us-east-2',
};

const stackProps = {
  logLevel: process.env.LOG_LEVEL || 'INFO',
  model: process.env.MODEL || 'base',
  domainName: process.env.DOMAIN_NAME || '',
  twilioHostName: process.env.TWILIO_HOST_NAME || '',
  nimHostName: process.env.NIM_HOST_NAME || '',
  capacityReservationId: process.env.CAPACITY_RESERVATION_ID || '',
  vendorName: process.env.VENDOR_NAME || '',
  containerName: process.env.CONTAINER_NAME || '',
  containerTag: process.env.CONTAINER_TAG || '',
};

const app = new App();

new NIMVoiceBot(app, 'NIMVoiceBot', {
  ...stackProps,
  env: devEnv,
});

app.synth();
