import {
  Certificate,
  CertificateValidation,
} from 'aws-cdk-lib/aws-certificatemanager';
import { IHostedZone, HostedZone } from 'aws-cdk-lib/aws-route53';

import { Construct } from 'constructs';

interface CertificateResourceProps {
  domainName: string;
  twilioHostName: string;
  nimHostName: string;
}
export class CertificateResources extends Construct {
  public readonly twilioCertificate: Certificate;
  public readonly nimCertificate: Certificate;
  public readonly hostedZone: IHostedZone;

  constructor(scope: Construct, id: string, props: CertificateResourceProps) {
    super(scope, id);

    this.hostedZone = HostedZone.fromLookup(this, 'HostedZone', {
      domainName: props.domainName,
    });

    this.twilioCertificate = new Certificate(this, 'TwilioCertificate', {
      domainName: `${props.twilioHostName}.${props.domainName}`,
      validation: CertificateValidation.fromDns(this.hostedZone),
    });

    this.nimCertificate = new Certificate(this, 'NimCertificate', {
      domainName: `${props.nimHostName}.${props.domainName}`,
      validation: CertificateValidation.fromDns(this.hostedZone),
    });
  }
}
