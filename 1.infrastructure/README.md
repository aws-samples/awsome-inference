## Infrastructure

This directory contains examples and reference scripts and templates for you to be able to set up your infrastructure on AWS to be able to perform inference.

The major components of this directory are:
```bash
|-- 0_setup_vpc/                      # CloudFormation templates for reference VPC
|-- 1_setup_cluster/                  # Scripts to create your cluster
`-- ...
// Other directories
```

## 🏁 Getting Started <a name = "getting_started"></a>

These instructions will get you a copy of the project up and running on your AWS Account for development and testing purposes. See [deployment](#deployment) for notes on how to deploy the project on a live system.

### 0. Option 1: [Linux] Install Package via scripts on aws-do-eks repository

Link to the repository [aws-do-eks](https://github.com/aws-samples/aws-do-eks/tree/main/Container-Root/eks/ops/setup)

```bash
# aws-cli
./install-aws-cli.sh

# eksctl
./install-eksctl.sh

# kubectl
./install-kubectl.sh

# docker
./install-docker.sh

# helm
./install-helm.sh
```


### 0. Option 2: Install Package following instruction

##### 1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Mac OS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Windows
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

##### 2. Install [eksctl](https://eksctl.io/installation/)
##### 3. Install [kubectl](https://kubernetes.io/docs/tasks/tools/)
##### 4. Install [docker](https://docs.docker.com/get-docker/)
##### 5. Install [helm](https://helm.sh/docs/intro/install/)


## `aws configure`
Run aws configure (`us-east-2` in this whole example section) to get your command line ready to interact with your AWS Account.
```bash
aws configure
```

## Setup VPC <a name = "setup_vpc"></a>

This sub-directory (`0_setup_vpc/`) contains CloudFormation scripts for you to be able to spin up a VPC, and all other related resources. For more information on a VPC, check out [What is Amazon VPC?](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html).

#### Files & Directories
1. `vpc-cf-example.yaml`: This CloudFormation template deploys a VPC, with a pair of public and private subnets spread across two Availability Zones. It deploys an internet gateway, with a default route on the public subnets. It deploys a pair of NAT gateways (one in each AZ), and default routes for them in the private subnets. This template format was borrowed from [here](https://docs.aws.amazon.com/codebuild/latest/userguide/cloudformation-vpc-template.html).

#### Setup Stack
To create a stack using the example CloudFormation template. Please navigate to the CloudFormation console and deploy. The VPC from the template at `0_setup_vpc/vpc-cf-example.yaml`.


## Setup EKS Cluster
This sub-directory (`1_setup_cluster/`) uses the following orchestrators for you to be able to set up a cluster for inference:

1. Amazon Elastic Kubernetes Service (EKS)
2. More coming soon...

This sub-directory contains yaml manifests, templates and examples to aid you in setting up clusters for inference.

### Files & Directories
1. `eks-p5-odcr-vpc.yaml`: This is a blank template that you can use to spin up an EKS cluster of p5 instances that you have reserved via the [On-Demand Capacity Reservation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html). 
2. `nims-cluster-config-example.yaml`: This is an example config file that you can use with EKS (as-is, or with modifications) to set up an EKS cluster. Make sure you follow the `project` README and make changes to suit your own use-case.
3. `trtllm-cluster-config-example.yaml`: This is an example config file that you can use with EKS (as-is, or with modifications) to set up an EKS cluster. Make sure you follow the project README and make changes to suit your own use-case.


This step assuming you have a VPC stack ready from the previous step, with region in `us-east-2`. Base on the target deployments, there are example manifests which can be edited to setup an EKS cluster:

1. 1_setup_cluster/nims-cluster-config-example.yaml
2. 1_setup_cluster/trtllm-cluster-config-example.yaml

Before creating an EKS cluster from the example manifest, please make sure the below parameters in the example manifest are updated:

1. `$PLACEHOLDER_VPC_ID`
2. `$PLACEHOLDER_SUBNET_PRIVATE_1`
3. `$PLACEHOLDER_SUBNET_PRIVATE_2`
4. `$PLACEHOLDER_SUBNET_PUBLIC_1`
5. `$PLACEHOLDER_SUBNET_PUBLIC_2`
6. `$INSTANCE_TYPE`
7. `$PUBLIC_KEYPAIR_NAME`
8. `$SECURITY_GROUP_IDS`

For 1 to 5, the information can be found by below command, where the `<YOUR_VPC_STACK_NAME>` was set in the [Setup VPC](#setup_vpc) step during stack creation in the CloudFormation. Grab the IDs of the VPC, PublicSubnet1, PublicSubnet2, PrivateSubnet1 and PrivateSubnet2.

```bash
aws cloudformation describe-stacks --stack-name <YOUR_VPC_STACK_NAME>
```

For 7 and 8, ,ake sure you change the security group id (`$SECURITY_GROUP_IDS`) and public key (`$PUBLIC_KEYPAIR_NAME`) to personalize ssh access to your own account. 


**Make sure you change up any fields you want to in the cluster configuration at this point!**

Some potential things you may want to change:
1. Name of cluster (make sure env is the same as name of cluster)
2. Name of managed node group(s)
3. Region: This example uses region `us-east-2`
4. K8s version: This example uses `1.29`
5. Instance type and instance prefix (the prefix is completely optional)
6. Change efaEnabled depending on instance type. 
7. Capacity (min, max, desired capacity): This example uses 1, 2, 1.
8. Volume size
9. Capacity Reservation: Comment out if you're not using reserved capacity (all 3 lines)


**Do NOT change:**

1. Any of the ids under vpc
2. Add ons
3. iam addons
4. Override Bootstrap command: You can comment all of this out except the last 4 lines. At a minimum, your `overrideBootstrapCommand` section should look like
```bash
    overrideBootstrapCommand: |
        /etc/eks/bootstrap.sh <CLUSTER_NAME>      
        nvidia-ctk runtime configure --runtime=containerd --set-as-default
        systemctl restart containerd
        echo "Bootstrapping complete!" 
```
 These lines are necessary for the node group to be able to join the EKS cluster! DO NOT DELETE. Make sure that the <CLUSTER_NAME> in line `/etc/eks/bootstrap.sh` has the same name as the one you set for cluster-name


Once all the changes (as required) are done, to create an EKS Cluster and NodeGroup:

```bash
cd 1_setup_cluster
eksctl create cluster -f <EXAMPLE_MANIFEST>.yaml
```

Note: If you make changes to your nodegroup after this step, you can just run
```bash
eksctl create nodegroup -f <EXAMPLE_MANIFEST>.yaml  # (or any other config file, as required)
```