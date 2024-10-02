# Steps to create EKS cluster with EFS

## 1. Install CLIs

### a. Install AWS CLI (steps [here](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))

```
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### b. Install Kubernetes CLI (steps [here](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html))

```
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
```

### c. Install EKS CLI (steps [here](https://eksctl.io/installation/))

```
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
```

### d. Install Helm CLI (steps [here](https://docs.aws.amazon.com/eks/latest/userguide/helm.html))

```
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh
```

## 2. Create an EKS cluster

In this example we create an EKS cluster consisting of two `g5.12xlarge` compute nodes, each with four NVIDIA A10G GPUs and `c5.2xlarge` CPU node as control plane. We also setup EFA between the compute nodes.

### a. Configure AWS CLI

```
aws configure
```

### b. Create a config file for EKS cluster creation

We have provided an example file here: [p5-trtllm-cluster-config.yaml](./p5-trtllm-cluster-config.yaml)

```
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: trtllm-inference-cluster
  region: us-east-1
  version: "1.30"

vpc:
  id: $PLACEHOLDER_VPC_ID
  subnets:
    private:
      us-east-1a:
        id: $PLACEHOLDER_SUBNET_PRIVATE_1
    public:
      us-east-1a:
        id: $PLACEHOLDER_SUBNET_PUBLIC_1
        
  clusterEndpoints:
    privateAccess: true
    publicAccess: true
      
cloudwatch:
  clusterLogging:
    enableTypes: ["*"]  

iam:
  withOIDC: true

            
managedNodeGroups:
  - name: cpu-node-group
    instanceType: c5.2xlarge
    minSize: 0
    desiredCapacity: 0
    maxSize: 1
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        ebs: true
        efs: true
        awsLoadBalancerController: true
        cloudWatch: true
        albIngress: true
  - name: gpu-compute-node-group
    instanceType: p5.48xlarge
    instancePrefix: trtllm-compute-node 
    privateNetworking: true
    efaEnabled: true
    minSize: 0
    desiredCapacity: 2
    maxSize: 2
    volumeSize: 500
    # comment out capacityReservation if you do not need ODCR
    capacityReservation:
      capacityReservationTarget:
        capacityReservationID: "cr-xxxxxxxxxxxxxx"
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        ebs: true
        efs: true
        awsLoadBalancerController: true
        cloudWatch: true
        albIngress: true
        externalDNS: true
        certManager: true
        autoScaler: true
```


### c. Create the EKS cluster

```
eksctl create cluster -f p5-trtllm-cluster-config.yaml
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

Follow the steps to create an EFS file system: https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/efs-create-filesystem.md. Make sure you mount subnets in the last step correctly. This will affect whether your nodes are able to access the created EFS file system.

## 5. Test

Follow the steps to check if your EFS file system is working properly with your nodes: https://github.com/kubernetes-sigs/aws-efs-csi-driver/tree/master/examples/kubernetes/multiple_pods. This test is going to mount your EFS file system on all of your available nodes and write a text file to the file system.

## 6. Create an PVC for the created EFS file system

We have provided an example in here: [pvc](./pvc/). This folder contains three files: `pv.yaml`, `claim.yaml`, and `storageclass.yaml`. Make sure you modify the `pv.yaml` file and change the `volumeHandle` value to your own EFS file system ID.

pv.yaml

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv
spec:
  capacity:
    storage: 200Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: fs-0cf1f987d6f5af59c # Change to your own ID
```

claim.yaml

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 200Gi
```

storageclass.yaml

```
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
```

Run the below command to deploy:

```
kubectl apply -f pvc/
```
