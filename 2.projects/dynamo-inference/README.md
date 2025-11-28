# Dynamo Inference on AWS

This repository provides production-ready container images and deployment manifests for running [NVIDIA Dynamo](https://github.com/ai-dynamo/dynamo) inference workloads on AWS infrastructure with high-performance EFA networking.

---

## Overview

### What is NVIDIA Dynamo?

NVIDIA Dynamo is an open-source inference runtime designed for serving large language models (LLMs) at scale. It provides a disaggregated architecture that separates the prefill and decode phases of LLM inference, enabling each phase to scale independently across multiple GPU nodes for optimal resource utilization.

### How Dynamo Differs from Other Inference Solutions

Dynamo introduces a distributed inference approach that separates traditionally coupled inference stages. This design allows organizations to achieve better cost-performance ratios compared to monolithic inference servers. Key characteristics include:

- **Disaggregated prefill and decode** — The computationally intensive prefill phase and memory-bound decode phase run on separate GPU pools
- **KV-cache transfer** — Efficiently moves key-value cache tensors between nodes using high-bandwidth EFA interconnects
- **Multiple backend support** — Compatible with TensorRT-LLM, vLLM, and other inference backends
- **Kubernetes-native** — Designed for cloud-native deployments on Amazon EKS and HyperPod

Optional GPU-direct communication patterns using NIXL (NVIDIA Inference Xfer Library) and UCX can be enabled for maximum performance when available.

---

## Inference Modes

### Aggregated Inference

Aggregated inference runs the full inference pipeline (prefill and decode) on a single node or tightly coupled GPU set. This deployment model offers:

- All inference phases execute on the same GPU(s)
- No inter-node KV-cache transfer overhead
- Simpler deployment and debugging
- Suitable for smaller models or lower-throughput scenarios

Use aggregated inference when starting with Dynamo or when workload characteristics don't require phase separation.

### Disaggregated Inference

Disaggregated inference separates the prefill and decode phases across different GPU pools. This repository demonstrates how to:

- Run prefill workers on compute-optimized nodes (handling prompt processing)
- Run decode workers on memory-bandwidth-optimized nodes (handling token generation)
- Transfer KV-cache between phases using EFA's high-bandwidth networking

Choose disaggregated inference for production workloads with high request concurrency, large context lengths, or when independent scaling of each phase provides cost benefits.

---

## Architecture Summary

The following diagram illustrates the high-level components in a disaggregated Dynamo deployment on AWS instances with supported GPUs:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Client Requests                               │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     Dynamo Frontend Service                             │
│                  (HTTP API - No GPU Required)                           │
└───────────────┬─────────────────────────────────────────┬───────────────┘
                │                                         │
                ▼                                         ▼
┌───────────────────────────────┐     ┌───────────────────────────────────┐
│       Prefill Workers         │     │        Decode Workers             │
│  ┌─────────────────────────┐  │     │  ┌─────────────────────────────┐  │
│  │   GPU Instance          │  │     │  │   GPU Instance              │  │
│  │   Supported GPUs        │  │     │  │   Supported GPUs            │  │
│  │   EFA Adapters          │  │     │  │   EFA Adapters              │  │
│  └─────────────────────────┘  │     │  └─────────────────────────────┘  │
└───────────────┬───────────────┘     └───────────────┬───────────────────┘
                │                                     │
                └──────────────────┬──────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │     KV-Cache Transfer        │
                    │   (EFA / UCX / NIXL)         │
                    └──────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │    FSx for Lustre Storage    │
                    │    (Model Weights & Engines) │
                    └──────────────────────────────┘
```

---

## Dynamo Inference on AWS

To leverage disaggregated inference on AWS, [Elastic Fabric Adapter (EFA)](https://aws.amazon.com/hpc/efa/) provides the critical high-bandwidth, low-latency networking required for efficient KV-cache transfer between nodes. This repository provides:

- **Base EFA image** with optimized drivers, libraries, and NCCL configuration
- **Dynamo runtime images** with TensorRT-LLM and backend support
- **Production-ready Kubernetes manifests** for EKS deployment
- **Automated build scripts** for custom container images
- **SSH-enabled images** for distributed training and multi-node operations

Deployment targets include:

| Platform | Description |
|----------|-------------|
| Amazon EKS | Managed Kubernetes with GPU node pools and autoscaling |
| Amazon SMHP with EKS | Enhanced EKS with integrated cluster lifecycle management |
| Amazon SMHP with SLURM | HPC-style Slurm scheduling on Sagemaker |

---

## Prerequisites

Before deploying these examples, ensure you have:

- AWS account with permissions for EC2, EKS, ECR, and VPC resources
- Docker or compatible container runtime installed locally
- Access to EC2 instances with supported GPUs and EFA
- Amazon EKS cluster (version 1.28+) with GPU-enabled node groups
- kubectl configured for cluster access
- Helm 3.x installed
- AWS CLI v2 configured
- (Optional) NVIDIA Container Toolkit for local builds

---

## AWS Services Used

This solution leverages the following AWS services:

| Service | Purpose |
|---------|---------|
| Amazon EC2  | GPU compute instances with supported GPUs for inference workloads |
| Elastic Fabric Adapter (EFA) | High-bandwidth low-latency networking for KV-cache transfer |
| Amazon ECR | Container image registry for storing Docker images |
| Amazon EKS | Kubernetes orchestration platform |
| FSx for Lustre | High-performance parallel filesystem for model storage |
| Amazon VPC | Network isolation and security groups |

---

## Build

### Supported Architectures

| Architecture | Status |
|--------------|--------|
| x86_64 (amd64) | ✅ Fully Supported |
| ARM64 (Graviton) | 🚧 Not tested |

### Base Image (EFA-enabled)

The base image includes EFA drivers, libfabric, UCX, NCCL, and AWS OFI NCCL plugin:

```bash
docker build -f Dockerfile.base -t aws-efa-base:latest .
```

**Key components:**
- CUDA 12.8.1 runtime and development libraries
- EFA installer with OpenMPI support
- Libfabric 2.3.0 with EFA provider
- UCX 1.19.0 with EFA and GDRCopy support
- NCCL 2.25+ with AWS OFI NCCL plugin
- NIXL 0.7.1 for GPU-direct transfers (C++ and Python)
- GDRCopy 2.4.1

**Expected image size:** ~8-9 GB

### Dynamo Image with TensorRT-LLM

Extended image with Dynamo runtime and TensorRT-LLM backend:

```bash
docker build -f Dockerfile.python-base -t dynamo-trtllm:latest .
```

**Additional components:**
- Python 3.12 with TensorRT-LLM dependencies
- SSH server for distributed operations
- Torch 2.x with CUDA support
- TensorRT-LLM runtime libraries

**Expected image size:** ~34 GB

### Build Options

```bash
# Build with specific CUDA architecture
docker build --build-arg CUDA_ARCH=86 -f Dockerfile.base -t aws-efa-base:sm86 .

# Build without cache
docker build --no-cache -f Dockerfile.base -t aws-efa-base:latest .

# Build and push to ECR
./build-dynamo.sh --push
```

---

## Prebuilt Images

Pre-built container images optimized for supported GPU instances are available:

```bash
# Pull base EFA image
docker pull public.ecr.aws/[your-registry]/aws-efa-base:latest

# Pull Dynamo with TensorRT-LLM
docker pull public.ecr.aws/[your-registry]/dynamo-trtllm:latest
```

---

## Run

### Quick Start (5 minutes)

#### 1. Prepare Environment

```bash
# Set namespace and version
export NAMESPACE=default
export RELEASE_VERSION=0.6.1

# Label GPU nodes for CUDA 12.x
kubectl get nodes -l node.kubernetes.io/instance-type -o name | \
  xargs -I {} kubectl label {} cuda-driver=cuda12 --overwrite
```

#### 2. Install Dynamo Platform

```bash
# Install CRDs and platform
helm fetch https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-crds-${RELEASE_VERSION}.tgz
helm fetch https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${RELEASE_VERSION}.tgz

helm install dynamo-crds dynamo-crds-${RELEASE_VERSION}.tgz --namespace ${NAMESPACE}
helm install dynamo-platform dynamo-platform-${RELEASE_VERSION}.tgz --namespace ${NAMESPACE}

# Patch etcd for compatibility
kubectl patch statefulset dynamo-platform-etcd -n ${NAMESPACE} -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"etcd","image":"docker.io/bitnamilegacy/etcd:3.5.18-debian-12-r5"}]}}}}'

# Wait for readiness
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=dynamo-platform -n ${NAMESPACE} --timeout=300s
```

#### 3. Configure Storage

```bash
# Edit FSx configuration with your subnet and security group
vi 01-fsx-storage.yaml  # Replace subnet-xxx and sg-xxx

# Apply storage configuration
kubectl apply -f 01-fsx-storage.yaml

# Verify PVC binding
kubectl get pvc fsx-claim -n ${NAMESPACE}
```

#### 4. Deploy Inference

```bash
# Apply engine configuration
kubectl apply -f 02-engine-config.yaml

# Deploy disaggregated inference
kubectl apply -f 03-dynamo-deployment.yaml

# Monitor deployment (wait 10-15 minutes for model loading)
watch kubectl get pods -n ${NAMESPACE}
```

#### 5. Test Deployment

```bash
# Health check
kubectl run -it --rm test --image=curlimages/curl -- \
  curl http://dynamo-disaggregated-frontend.default.svc.cluster.local:8000/health | jq .

# Generate completion
curl -X POST http://dynamo-disaggregated-frontend.default.svc.cluster.local:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
  "model": "meta-llama/Llama-3.2-3B",
  "prompt": "Explain quantum computing:",
  "max_tokens": 50
  }' | jq .
```

For detailed deployment instructions, refer to **DEPLOYMENT_GUIDE.md**.

---

## Configuration

### Backend Options for KV-Cache Transfer

#### DEFAULT (UCX with EFA) - Recommended
```yaml
cache_transceiver_config:
  backend: default
```
- Automatically configures UCX with AWS EFA
- Production-ready with optimal compatibility
- No additional configuration required

#### NIXL (GPU-Direct)
```yaml
cache_transceiver_config:
  backend: nixl
```
- NVIDIA Inference Xfer Library for GPU-direct transfers
- Requires compatible GPU architecture
- Best performance for supported configurations

#### Switching Backends

```bash
# Edit ConfigMap
kubectl edit configmap trtllm-engine-config

# Restart workers to apply changes
kubectl rollout restart deployment/dynamo-disaggregated-backend-prefill
kubectl rollout restart deployment/dynamo-disaggregated-backend-decode
```

---

## Troubleshooting

### Common Issues

#### SSH Daemon Missing
```
Error: exec: "/usr/sbin/sshd": no such file or directory
```
**Solution:** Use the SSH-enabled Docker image from Dockerfile.python-base

#### CUDA Symbol Errors
```
ImportError: undefined symbol: cudaLibraryGetKernel, version libcudart.so.12
```
**Solution:** Ensure nodes are labeled with `cuda-driver=cuda12`

#### MPI Header Missing During Build
```
fatal error: mpi.h: No such file or directory
```
**Solution:** Install EFA dependencies before EFA installer (see Dockerfile.base lines 157-165)

For detailed troubleshooting, see **QUICK_FIX.md** and **SSH_FIX_GUIDE.md**.

---

## References

| Resource | Link |
|----------|------|
| NVIDIA Dynamo GitHub | [https://github.com/ai-dynamo/dynamo](https://github.com/ai-dynamo/dynamo) |
| NVIDIA Dynamo Documentation | [https://docs.nvidia.com/dynamo](https://docs.nvidia.com/dynamo) |
| AWS EFA Documentation | [https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html) |
| Amazon EKS User Guide | [https://docs.aws.amazon.com/eks/latest/userguide/](https://docs.aws.amazon.com/eks/latest/userguide/) |
| AWS GPU Instances | [https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing) |
| TensorRT-LLM | [https://github.com/NVIDIA/TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM) |
| FSx for Lustre | [https://aws.amazon.com/fsx/lustre/](https://aws.amazon.com/fsx/lustre/) |
| Awesome Distributed Training | [https://github.com/aws-samples/awsome-distributed-training](https://github.com/aws-samples/awsome-distributed-training) |

---

## License

This library is licensed under the MIT-0 License. See the [LICENSE](../../LICENSE) file for details.

---

## Contributing

[Contributions](../../CONTRIBUTING.md) are welcome. Please submit issues and pull requests following standard GitHub practices. 

---

**Last Updated:** November 2025
