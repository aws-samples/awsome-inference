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
1. `capacity_block/`: If you are using [Capacity Blocks for ML](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html), this directory is for you. This directory contains a YAML cluster configuration (`nims-cluster-config-example-cb.yaml`) without any nodegroups, and a CloudFormation template to create self-managed nodegroups (`capacity-block-eksctl-nodegroup.yaml`). For more information on deployment, check out the [Capacity Blocks](https://github.com/aws-samples/awsome-inference/tree/capacity-block-eks/1.infrastructure#capacity-blocks) section below.
2. `eks-p5-odcr-vpc.yaml`: This is a blank template that you can use to spin up an EKS cluster of p5 instances that you have reserved via the [On-Demand Capacity Reservation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html). 
3. `nims-cluster-config-example.yaml`: This is an example config file that you can use with EKS (as-is, or with modifications) to set up an EKS cluster. Make sure you follow the `project` README and make changes to suit your own use-case.
4. `trtllm-cluster-config-example.yaml`: This is an example config file that you can use with EKS (as-is, or with modifications) to set up an EKS cluster. Make sure you follow the project README and make changes to suit your own use-case.
5. `multinode-triton-trtllm-inference/`: This directory contains the guide and yaml file for creating EKS cluster for Triton TRT-LLM multi-node inference.

**Note: The instructions below pertain to creating an EKS cluster **only if** you are not using [Capacity Blocks](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html). If you are using Capacity Blocks, please check out the [Capacity Blocks](https://github.com/aws-samples/awsome-inference/tree/capacity-block-eks/1.infrastructure#capacity-blocks) section below.
**

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

For 7 and 8, make sure you change the security group id (`$SECURITY_GROUP_IDS`) and public key (`$PUBLIC_KEYPAIR_NAME`) to personalize ssh access to your own account. 


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

## Capacity Blocks
Currently, [Capacity Blocks for ML](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html) have the restriction that they cannot be in a *managed node group*. Therefore, in this case, we would need to provision them as part of a [_self-managed node group_](https://docs.aws.amazon.com/eks/latest/userguide/worker.html). Complete the following steps to provision an EKS cluster with self-managed Capacity Block nodes:

1. Deploy a bare-bones EKS cluster. The configuration file for this can be found in `capacity_block/nims-cluster-config-example-cb.yaml`. This config file creates an EKS cluster without the node group. It also adds on additional iam, cloudwatch and vpc-cni plugins.
```
cd capacity_block
eksctl create cluster -f nims-cluster-config-example-cb.yaml
```

2. Once the cluster is created, we will proceed to create the self-managed node group. Note: self-managed here means that you will not be able to see the node group on your eks console, but you should be able to see the nodes by running `kubectl get nodes` once your cluster is provisioned. You can find the template for the CloudFormation stack in `capacity-block-eksctl-nodegroup.yaml`. You may do this via the CloudFormation console, similar to how you did for provisioning the VPC. Some important parameters:
* `ClusterName` this needs to be the same as the cluster you created above, default to `eks-p5-odcr-vpc`
* `ClusterControlPlaneSecurityGroup` grab this by visiting the EKS Console > **Cluster** > **Networking** > **Additional Security Group**
* `NodeGroupName` choose a name for your nodegroup
* `NodeAutoScalingGroupMinSize`, `NodeAutoScalingGroupDesiredCapacity`, `NodeAutoScalingGroupMaxSize` change these depending on scaling needs
* `NodeImageIdSSMParam` defaults to the [EKS GPU AMI 1.29](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html) but you can override this with the `NodeImageId` parameter.
* `KeyName` if you'd like to ssh into these compute nodes, please provide the `KeyName` you'd like to use
* `VpcId`, `Subnets` make sure these are the same as the ones provided while creating the cluster above
* `CapacityBlockId` the ID of the CapacityBlock reservation that you made
* This sets up a [security group for EFA](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html#efa-start-security).

3. Once the nodegroup is created and the CloudFormation stack's creation is complete, we need to ensure that the node joins the cluster. To do so, we will need to change the permissions associated with the `ConfigMap` of the EKS cluster. Specifically, you'd need to follow these steps:

    3.1 Check to see if you already have an `aws-auth` defined in your `ConfigMap`.
    ```
    kubectl describe configmap -n kube-system aws-auth
    ```
    This will either give you a description of the existing `aws-auth` configuration, or you will see an error that looks like `Error from server (NotFound): configmaps "aws-auth" not found`. Follow 3.2 and skip 3.3 if you are shown the configuration. Otherwise, if you see an error, skip 3.2 and follow 3.3.

    3.2 If you don't see an error (i.e., if you are shown an `aws-auth` configuration)
      3.2.1 Open the existing `ConfigMap` for editing.
   ```
   kubectl edit -n kube-system configmap/aws-auth
   ```
      3.2.2 If you already see a `mapRoles` entry, add a new one that looks like:
   ```bash
   [...]
    data:
      mapRoles: |
        - rolearn: <ARN of instance role (not instance profile)>
          username: system:node:{{EC2PrivateDNSName}}
          groups:
            - system:bootstrappers
            - system:nodes
    [...]
   ```
      3.2.3 Save the file and exit your text editor. 
   
    3.3. If you see an error (`Error from server (NotFound): configmaps "aws-auth" not found`), then you'd need to download the template `ConfigMap` file and apply it
      3.3.1 Download the `ConfigMap` template
   ```
   curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml
   ```
      3.3.2 In the downloaded `aws-auth-cm.yaml` file, set the `rolearn` value to the `NodeInstanceRole` that you grabbed from the CloudFormation stack. You may choose to do this via a text editor, or replacing `my-node-instance-role` and running:
   ```
   sed -i.bak -e 's|<ARN of instance role (not instance profile)>|my-node-instance-role|' aws-auth-cm.yaml
   ```
      3.3.3 Apply the updated config
   ```
   kubectl apply -f aws-auth-cm.yaml
   ```

4. Once you complete step 3 (either option), you may check if the node joined your cluster with
```
kubectl get nodes
```

5. Once you've confirmed that the nodes have joined, you can go ahead and install additional plugins.

   5.1 To install the [K8s NVIDIA CNI Plugin](https://github.com/NVIDIA/k8s-device-plugin), run
   ```
   kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml
   ```

   5.2 If using EFA, make sure to install the [EFA CNI Plugin](https://docs.aws.amazon.com/eks/latest/userguide/node-efa.html)
   ```
   kubectl apply -f https://raw.githubusercontent.com/aws-samples/aws-efa-eks/main/manifest/efa-k8s-device-plugin.yml
   ```
