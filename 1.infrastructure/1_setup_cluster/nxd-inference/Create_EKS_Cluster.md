# Steps to create EKS cluster with EFS

In this example we create an EKS cluster consisting of two `trn1.32xlarge` compute nodes. We also setup EFA between the compute nodes.

### a. Configure AWS CLI

```
aws configure
```

### b. Create a config file for EKS cluster creation

We have provided an example file here: [trn1-nxd-cluster-config..yaml](./trn1-nxd-cluster-config.yaml)

```
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: nxdi-inference-cluster
  region: $REGION
  version: "1.00"

vpc:
  id: $PLACEHOLDER_VPC_ID
  subnets:
    private:
      $AVAILABILITY_ZONE_1:
        id: $PLACEHOLDER_SUBNET_PRIVATE_1
    public:
      $AVAILABILITY_ZONE_1:
        id: $PLACEHOLDER_SUBNET_PUBLIC_1
      $AVAILABILITY_ZONE_2:
        id: $PLACEHOLDER_SUBNET_PUBLIC_2
        
  clusterEndpoints:
    privateAccess: true
    publicAccess: true
      
cloudwatch:
  clusterLogging:
    enableTypes: ["*"]  

iam:
  withOIDC: true

# Adding additional section to Cluster (eksctl) for any controllers you may want to install. Uncomment as required. 
wellKnownPolicies:
#   ebsCSIController: true      # Adds policies for using the ebs-csi-controller
  efsCSIController: true      # Adds policies for using the efs-csi-controller  

addons:
  - name: vpc-cni
    version: 1.18.1-eksbuild.1
    configurationValues: '{"env":{"ENABLE_PREFIX_DELEGATION":"true", "ENABLE_POD_ENI":"true", "POD_SECURITY_GROUP_ENFORCING_MODE":"standard"},"enableNetworkPolicy": "true"}'
    resolveConflicts: overwrite      
  - name: amazon-cloudwatch-observability
    version: v1.16.4-eksbuild.1
  # - name: aws-ebs-csi-driver
  #   version: v1.26.0-eksbuild.1
  - name: aws-efs-csi-driver     
    version: v2.1.9-eksbuild.1  

managedNodeGroups:
  - name: trn-compute-node-group
    instanceType: trn1.32xlarge
    instancePrefix: trtllm-compute-node 
    subnets:
      - $PLACEHOLDER_SUBNET_PRIVATE_1
    privateNetworking: true
    efaEnabled: true
    minSize: 0
    desiredCapacity: 2
    maxSize: 2
    volumeSize: 500
    # comment out capacityReservation if you do not need ODCR
    #capacityReservation:
      #capacityReservationTarget:
        #capacityReservationID: "$CR_ID"
    ami: ami-07c8bc6b0bb890e9e
    amiFamily: AmazonLinux2
    ssh:
      publicKeyName: $PUBLIC_KEYPAIR_NAME
      sourceSecurityGroupIds: [$SECURITY_GROUP_IDS]
    updateConfig:
      maxUnavailablePercentage: 50
    iam:
      withAddonPolicies:
        externalDNS: true
        certManager: true
        autoScaler: true
        cloudWatch: true
        ebs: true
        efs: true
        fsx: true
        imageBuilder: true
        xRay: true
        awsLoadBalancerController: true
        albIngress: true
    
```


### c. Create the EKS cluster

```
eksctl create cluster -f trn1-nxdi-cluster-config.yaml
```

## 3. (Optional) Capacity Blocks

If you have Capacity Blocks for P5 or P4 instances, you can follow the [steps here](https://github.com/aws-samples/awsome-inference/tree/main/1.infrastructure#capacity-blocks) to create a self-managed nodegroup and add to your existing EKS cluster.


## 4. Create an EFS file system

To enable multiple pods deployed to multiple nodes to load shards of the same model so that they can used in coordination to serve inference request too large to loaded by a single GPU, we'll need a common, shared storage location. In Kubernetes, these common, shared storage locations are referred to as persistent volumes. Persistent volumes can be volume mapped in to any number of pods and then accessed by processes running inside of said pods as if they were part of the pod's file system. We will be using EFS as persistent volume.

Additionally, we will need to create a persistent-volume claim which can use to assign the persistent volume to a pod.
### a. Create an IAM role

Follow the steps to create an IAM role for your EFS file system: https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html#efs-create-iam-resources. This role will be used later when you install the EFS CSI Driver.

### b. Install EFS CSI driver

Install the EFS CSI Driver through the Amazon EKS add-on in AWS console: https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html#efs-install-driver. Once it's done, check the Add-ons section in EKS console, you should see the driver is showing `Active` under Status.

### c. Create EFS file system

### Create EFS Filesystem
```bash
# Create EFS filesystem
aws efs create-file-system \
    --creation-token neuron-models-$(date +%s) \
    --performance-mode generalPurpose \
    --throughput-mode provisioned \
    --provisioned-throughput-in-mibps 1000 \
    --tags Key=Name,Value=neuron-disaggregated-efs

# Get the filesystem ID
EFS_ID=$(aws efs describe-file-systems \
    --query 'FileSystems[?Tags[?Key==`Name`&&Value==`neuron-disaggregated-efs`]].FileSystemId' \
    --output text)

# Create mount targets in each subnet
for subnet in subnet-xxx subnet-yyy subnet-zzz; do
    aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $subnet \
        --security-groups sg-your-efs-security-group
done
```


### EFS CSI Driver Installation
```bash
# Install EFS CSI Driver
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.7"

# Create StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${EFS_ID}
  directoryPerms: "0755"
EOF
```