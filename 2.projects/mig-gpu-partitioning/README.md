<!-- <p align="center">
  <a href="" rel="noopener">
 <img width=200px height=200px src="https://i.imgur.com/6wj0hh6.jpg" alt="Project logo"></a>
</p> -->

<h3 align="center">Configuring MIG on AWS EC2 Accelerated GPU Instances with EKS </h3>

---

<p align="center"> This directory contains information on how you can partition your GPU(s) for running smaller training/inference workloads.

Today’s Machine Learning (ML) workloads, including Foundation Model (FM) / Large Language Model (LLM) training and inference, require tremendous amounts of compute resources. For example, the [recent introduction of Llama 3.1 405B](https://ai.meta.com/blog/meta-llama-3-1/), with its staggering 405 billion parameters, exemplifies this trend towards increasing demands for compute resources. [Amazon EC2 accelerated instances](https://aws.amazon.com/ec2/instance-types/#accelerated-computing) with NVIDIA GPUs help parallelize training and inference workloads for a variety of use cases, including [ML](https://aws.amazon.com/ai/machine-learning/) and [High Performance Computing](https://aws.amazon.com/hpc/) (HPC). 

The challenge, however, is that not all ML workloads require the same amount of compute resources. With accelerated instances like the [Amazon EC2 P5](https://aws.amazon.com/ec2/instance-types/p5/) (p5.48xlarge / p5e.48xlarge), or the [Amazon EC2 P4](https://aws.amazon.com/ec2/instance-types/p4/) (p4d.24xlarge / p4de.24xlarge), customers would need to pay for the full instance of 8 GPUs. Additionally, some workloads may be too small to even run on a single GPU! To learn more about the specifics of GPU EC2 instances, check out this [developer guide](https://docs.aws.amazon.com/dlami/latest/devguide/gpu.html). 

In 2020, NVIDIA released [Multi-Instance GPU](https://www.nvidia.com/en-us/technologies/multi-instance-gpu/) (MIG), alongside the Ampere Architecture that powers the NVIDIA A100 ([EC2 P4](https://aws.amazon.com/ec2/instance-types/p4/)) and NVIDIA A10G ([EC2 G5](https://aws.amazon.com/ec2/instance-types/g5/)) GPUs. With MIG, administrators can partition a single GPU into multiple smaller GPU units (called “MIG devices”). Each of these smaller GPU units are fully isolated, with their own high-bandwidth memory, cache, and compute cores. To learn more about MIG, please check out the [MIG User Guide](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/?ref=blog.realvarez.com).

Today, we’ll walk you through setting up these MIG devices on an [Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks/) (EKS) cluster of a single p5.48xlarge instance. To set up this cluster, you can check out the [infrastructure](https://github.com/aws-samples/awsome-inference/tree/main/1.infrastructure) section on awsome-inference. Feel free to customize this sample to your own use-case and follow along!

## Prerequisite
#### Setup the EKS cluster
Please make sure the EKS cluster has been setup, either from a given example in [infrastructure](infrastructure). Amazon EKS is a managed service for running Kubernetes workloads on AWS. EKS provides you with a managed control plane, and lets you interact with the cluster via kubectl , Helm or something equivalent. 

Once you have your EKS cluster set up using the samples found in awsome-inference, you can find the name of your P5 node using 

```bash
kubectl get nodes -L node.kubernetes.io/instance-type
```

This should output something like

```bash
NAME                          STATUS ROLES  AGE   VERSION              INSTANCE-TYPE
ip-192-168-117-30.ec2.internal Ready <none> 3h10m v1.30.2-eks-1552ad0  p5.48xlarge 
```

You can grab the name of the accelerated instance and save it as an environment variable to make your life easier!
```bash
export accel_instance=ip-192-168-117-30.ec2.internal
```

## MIG Profiles
MIG allows you to partition your GPU(s) with each device being fully isolated, with it’s own memory, cache, and compute cores. This is done based on different memory profiles (aka MIG profiles). These MIG profiles determine the slices while partitioning the GPUs. 

Let’s take a look at the specs of a single p5.48xlarge instance:

* 8 x NVIDIA H100 GPUs
* 96 vCPUs
* 1 TB RAM
* 3200 Gbps of EFA

Each of these eight H100s is capable of 7 10GB slices. This means that for each p5.48xlarge, you can have up to 56 individual isolated GPU slices. To check what profiles are available to you, you can use [AWS Systems Managers’ Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) to ssm into your compute node. Once you ssm in, you can run

```bash
sudo nvidia-smi mig -lgip
```

This should output the different profiles available to you

```bash
+-----------------------------------------------------------------------------+
| GPU instance profiles: |
| GPU  Name  ID Instances  Memory  P2P SM DEC  ENC |
| Free/Total  GiB CE JPEG OFA |
|=============================================================================|
|  0 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  0 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  0 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  0 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  0 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  0 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  0 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
|  1 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  1 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  1 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  1 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  1 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  1 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  1 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
|  2 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  2 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  2 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  2 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  2 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  2 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  2 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
|  3 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  3 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  3 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  3 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  3 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  3 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  3 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
|  4 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  4 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  4 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  4 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  4 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  4 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  4 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
|  5 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  5 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  5 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  5 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  5 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  5 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  5 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
|  6 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  6 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  6 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  6 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  6 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  6 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  6 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
|  7 MIG 1g.10gb  19  7/7 9.75  No  16  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  7 MIG 1g.10gb+me 20  1/1 9.75  No  16  1  0  |
|  1  1  1  |
+-----------------------------------------------------------------------------+
|  7 MIG 1g.20gb  15  4/4 19.62 No  26  1  0  |
|  1  1  0  |
+-----------------------------------------------------------------------------+
|  7 MIG 2g.20gb  14  3/3 19.62 No  32  2  0  |
|  2  2  0  |
+-----------------------------------------------------------------------------+
|  7 MIG 3g.40gb 9  2/2 39.38 No  60  3  0  |
|  3  3  0  |
+-----------------------------------------------------------------------------+
|  7 MIG 4g.40gb 5  1/1 39.38 No  64  4  0  |
|  4  4  0  |
+-----------------------------------------------------------------------------+
|  7 MIG 7g.80gb 0  1/1 79.12 No  132 7  0  |
|  8  7  1  |
+-----------------------------------------------------------------------------+
```

## NVIDIA GPU Operator on EKS
The [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) uses Kubernetes' [operator framework](https://www.redhat.com/en/blog/introducing-the-operator-framework) to automate the management of all NVIDIA software components that are needed to provision and orchestrate GPUs. One of the key features supported is the support fo NVIDIA Multi-Instance GPU (MIG).

The operator installs:
* [NVIDIA Device Driver](https://www.nvidia.com/en-us/drivers/)
* [NVIDIA Feature GPU Discovery Service](https://github.com/NVIDIA/gpu-feature-discovery)
* [NVIDIA Node Feature Discovery Service](https://github.com/kubernetes-sigs/node-feature-discovery)
* [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
* [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
* [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit)
* And most importantly, **NVIDIA MIG Manager**
* ...

To install the NVIDIA GPU operator, you can run
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
   && helm repo update

helm upgrade gpu-operator \
    nvidia/gpu-operator \
    --set mig.strategy=mixed \
    --set devicePlugin.enabled=true \
    --set migManager.enabled=true \
    --set migManager.WITH_REBOOT=true \
    --set operator.defaultRuntime=containerd \
    --set devicePlugin.version=v0.17.0 \
    --set migManager.default=all-balanced
```

Note: Ignore the `mig.strategy=mixed` for now. We'll cover different MIG strategies in an upcoming section.

You can check the resources created by the GPU Operator by running `kubectl get pods`. Look out for something that looks like 
```bash
...
nvidia-mig-manager-xxxxx
...
```

## MIG Partition Strategies
NVIDIA provides us with two different strategies for creating MIG partitions and exposing them to Kubernetes: *single strategy* and *mixed strategy*.

### Single Strategy
In this strategy, a node only exposes a single type of MIG device partition across all GPUs. For example, if you choose the 20gb profile, all of your MIG partitions will be 20gb.

On a P5.48xlarge, you can create 56 x 10GB (`1g.10gb`) partitions. 

### Mixed Strategy
In this strategy, like the name suggests, you can create a "mix" of different partitions.

On a P5.48xlarge, you can create 16 x 20GB (`2g.20gb`), and 8 x 40GB (`4g.40gb`) partitions. 

## Create MIG devices
Since we have the NVIDIA MIG Manager installed, the beauty now is that all you need to do to configure partitions is label the node (using `kubectl` or something equivalent). The MIG Manager runs as a daemonset on all of the nodes; when it detects specific node labels (`mig.config`), it will use [mig-parted](https://github.com/NVIDIA/mig-parted) to create MIG devices.

### Single Strategy
Configure two 3g.40gb MIG partitions by adding a label on the GPU node
```bash
kubectl label nodes $accel_instance nvidia.com/mig.config=all-3g.40gb --overwrite
```

Once you label the node, you will see that the node no longer shows any GPUs (`nvidia.com/gpu` label = 0). Additionally, your node will now advertise 16 `3g.40gb` MIG devices. When you run `kubectl describe node`

```bash
...
    nvidia.com/gpu:         0
    nvidia.com/mig-3g.40gb  16
...
```

Note: Getting to this point could take some time. You will see a label `nvidia.com/mig.config.state=pending` on the node as the change propagates. Once the partitioning is complete, the label will change to `nvidia.com/mig.config.state=success`.

You can verify that it works by getting the nvidia plugin pods (`kubectl get po -n kube-system`) and running
```bash
kubectl exec dependencies-nvidia-device-plugin-crm7s -t -n kube-system -- nvidia-smi -L 
```

### Mixed Strategy
As mentioned above, the mixed strategy slices GPUs into multiple MIG device profile configurations. The MIG manager uses a Kubernetes `configmap` called `default-mig-parted-config`. You can take a look at this `configmap` by running `kubectl describe configmaps default-mig-parted-config`.

For example, when we labeled the node with `all-3g.40gb`, we get
```bash
...
all-3g.40gb:
    - devices: all
      mig-enabled: true
      mig-devices:
        "3g.40gb": 2
...
```

For the mixed strategy, this `configmap` needs to be edited. The `configmap` comes with profiles such as `all-balanced`. 

Firstly, if you tried the single strategy before this, configure the MIG strategy to `mixed`.
```bash
kubectl patch clusterpolicies.nvidia.com/cluster-policy \
    --type='json' \
    -p='[{"op":"replace", "path":"/spec/mig/strategy", "value":"mixed"}]'
```

You can now label your node
```bash
kubectl label nodes $accel_instance nvidia.com/mig.config=all-balanced --overwrite
```

This should create 2 x 10GB (`1g.10gb`), 1 x 20GB (`2g.20gb`), and 1 x 40GB (`4g.40gb`) partitions.

You can also `describe` the `configmap` to get
```bash
...
    all-balanced:
      - device-filter: [...]
        devices: all
        mig-enabled: true
        mig-devices:
          "1g.10gb": 2
          "2g.20gb": 1
          "4g.40gb": 1
...
```

Again, once the node label changes to `nvidia.com/mig.config.state=success`, you should see the multiple MIG device partitions listed in the node when you run `kubectl describe node`

```bash
...
  nvidia.com/mig-1g.10gb:      16
  nvidia.com/mig-2g.20gb:      8
  nvidia.com/mig-3g.40gb:      8
...
```

You can also verify that it works by getting the nvidia plugin pods (`kubectl get po -n kube-system`) and running
```bash
kubectl exec dependencies-nvidia-device-plugin-crm7s -t -n kube-system -- nvidia-smi -L 
``` 

## ⛏️ Built Using <a name = "built_using"></a>

- [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) - Scaling using Kubernetes
- [AWS EC2 Accelerated Instances](https://aws.amazon.com/ec2/instance-types/)
ADD NIMs LINKS
- [NVIDIA MIG](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)

## ✍️ Authors <a name = "authors"></a>

- [@amanrsh](https://github.com/amanshanbhag)
