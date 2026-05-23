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


## Supported Instance Types

Dynamo inference works across multiple AWS GPU instance types. The networking layer automatically adapts:

| Instance | GPU | GPUs/Node | EFA | KV Transfer | Verified |
|----------|-----|-----------|-----|-------------|----------|
| **p5en.48xlarge** | NVIDIA H200 141GB | 8 | 16x 200Gbps | NIXL LIBFABRIC RDMA | Yes — 8-GPU disagg, 600ms latency |
| **p5.48xlarge** | NVIDIA H100 80GB | 8 | 32x 100Gbps | NIXL LIBFABRIC RDMA | Yes |
| **p4d.24xlarge** | NVIDIA A100 40GB | 8 | 4x 100Gbps | NIXL LIBFABRIC RDMA | Compatible |
| **g6e.xlarge+** | NVIDIA L40S 48GB | 1-8 | None | TCP / vLLM connector | Yes — vLLM backend |
| **g5.xlarge+** | NVIDIA A10G 24GB | 1-8 | None | TCP / vLLM connector | Compatible |

### Instance-Specific Environment Variables

**P5/P5en (EFA RDMA):**
```bash
NIXL_BACKEND=LIBFABRIC
FI_PROVIDER=efa
FI_EFA_USE_DEVICE_RDMA=1
FI_EFA_ENABLE_SHM_TRANSFER=0
NIXL_SKIP_TOPOLOGY_CHECK=1
```

**G5/G6E (no EFA):**
```bash
# No EFA variables needed — Dynamo falls back to TCP/vLLM connector
# Use vLLM backend (python3 -m dynamo.vllm) for best performance
```

### Choosing a Backend

| Backend | Best For | Command |
|---------|----------|---------|
| **TRT-LLM** | Maximum throughput on P5/P5en | `python3 -m dynamo.trtllm` |
| **vLLM** | Flexibility, any GPU, no TensorRT | `python3 -m dynamo.vllm` |
| **Combined image** | Both backends available at runtime | Choose at deploy time |

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

### Dynamo Combined Image (vLLM + TRT-LLM)

A single image containing **both** vLLM and TRT-LLM backends, built from scratch with EFA/NIXL RDMA networking. This is a self-contained multi-stage build that does not depend on the base EFA image above.

```bash
docker build -f Dockerfile.dynamo-combined-efa -t dynamo-combined-efa:latest .
```

**Key components:**
- Dynamo 1.0.0 runtime (Rust + Python)
- vLLM 0.17.1 (PyTorch-native inference)
- TRT-LLM 1.3.0rc7 (TensorRT-optimized inference)
- NIXL 0.10.1 with UCX and libfabric plugins
- UCX v1.20.x with EFA, GDRCopy, CUDA support
- libfabric v2.3.0 with EFA provider
- AWS EFA installer 1.45.1
- CUDA 12.9 (devel), Python 3.12, Rust 1.93.1
- NATS v2.10.28 + etcd v3.5.21 (Dynamo service mesh)
- FFmpeg 7.1 (Apache-licensed codecs, for multimodal models)
- Built-in SBOM at `/SBOM.txt` and `/THIRD-PARTY-LICENSES`

**Architecture:** 7-stage multi-stage build

| Stage | Name | Purpose |
|-------|------|---------|
| 1 | `dynamo_base` | Rust, NATS, etcd, uv, sccache |
| 2 | `wheel_builder_base` | UCX, GDRCopy, libfabric, FFmpeg, AWS SDK |
| 3 | `wheel_builder` | NIXL + Dynamo Python wheels |
| 4 | `pytorch_base` | NGC PyTorch for TRT-LLM |
| 5 | `trtllm_framework` | TRT-LLM + PyTorch in venv |
| 6 | `vllm_framework` | vLLM + FlashInfer + LMCache |
| 7 | `final` | Combined runtime with EFA |

**Expected image size:** ~35-40 GB

**Prebuilt image:**
```bash
docker pull public.ecr.aws/v9l4g5s4/dynamo-combined:latest
```

### Build Options

```bash
# Build with specific CUDA architecture
docker build --build-arg CUDA_ARCH=86 -f Dockerfile.base -t aws-efa-base:sm86 .

# Build without cache
docker build --no-cache -f Dockerfile.base -t aws-efa-base:latest .

# Build combined image
./build.sh -b combined

# Build and push to ECR
./build.sh --push
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
# Set namespace and chart versions.
# As of 2026-04-20, public NGC (helm.ngc.nvidia.com/nvidia/ai-dynamo) publishes:
#   - dynamo-crds     latest public = 0.9.1
#   - dynamo-platform latest public = 1.0.1  (skip 1.0.0 — Blackwell crash)
# The two chart versions intentionally diverge: 1.0.x platform is compatible
# with 0.9.1 CRDs. Both downloads are anonymous (no NGC login required).
export NAMESPACE=default
export DYNAMO_CRDS_VERSION=0.9.1
export DYNAMO_PLATFORM_VERSION=1.0.1

# Label GPU nodes for CUDA 12.x
kubectl get nodes -l node.kubernetes.io/instance-type -o name | \
  xargs -I {} kubectl label {} cuda-driver=cuda12 --overwrite
```

#### 2. Install Dynamo Platform

```bash
# Install CRDs and platform — both are anonymous fetches, no NGC login needed.
helm fetch https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-crds-${DYNAMO_CRDS_VERSION}.tgz
helm fetch https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${DYNAMO_PLATFORM_VERSION}.tgz

helm install dynamo-crds     dynamo-crds-${DYNAMO_CRDS_VERSION}.tgz     --namespace ${NAMESPACE} --create-namespace
helm install dynamo-platform dynamo-platform-${DYNAMO_PLATFORM_VERSION}.tgz --namespace ${NAMESPACE}

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

## Kubernetes Deployment (Combined Image)

The `k8s/` directory contains production-tested manifests for deploying the combined image on Amazon EKS with EFA networking.

### Disaggregated Inference (1 GPU per worker)

```bash
kubectl apply -f k8s/dynamo-combined-disagg-1gpu.yaml -n <namespace>
```

Deploys one prefill worker pod and one decode worker pod, each using 1 GPU and 1 EFA device. KV-cache is transferred between nodes via NIXL over EFA RDMA.

### Disaggregated Inference (8 GPUs per node)

```bash
kubectl apply -f k8s/dynamo-combined-disagg-8gpu.yaml -n <namespace>
```

Deploys 8 data-parallel prefill workers on one node and 8 data-parallel decode workers on another, using all 16 EFA devices per node.

### EFA/NIXL Environment Variables

The following environment variables control NIXL transport over EFA:

| Variable | Value | Description |
|----------|-------|-------------|
| `NIXL_BACKEND` | `LIBFABRIC` | Use libfabric transport (EFA provider) |
| `FI_PROVIDER` | `efa` | Select EFA fabric provider |
| `FI_EFA_USE_DEVICE_RDMA` | `1` | Enable GPU-direct RDMA over EFA |
| `FI_EFA_ENABLE_SHM` | `0` | Disable shared memory (cross-node only) |
| `FI_EFA_ENABLE_SHM_TRANSFER` | `0` | Disable SHM transfer (cross-node only) |
| `NIXL_SKIP_TOPOLOGY_CHECK` | `1` | Skip NVSwitch topology validation (EFA) |
| `NIXL_LIBFABRIC_MAX_RAILS` | `1` | Number of EFA rails per worker |
| `NIXL_SIDE_CHANNEL_PORT` | `5700` | NIXL side channel port (increment per GPU) |

### Required Kubernetes Resources

For EFA-enabled pods on Amazon EKS:

```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
    vpc.amazonaws.com/efa: "1"
    hugepages-2Mi: 5120Mi
  requests:
    nvidia.com/gpu: "1"
    vpc.amazonaws.com/efa: "1"
    hugepages-2Mi: 5120Mi
```

Volume mounts for EFA and shared memory:

```yaml
volumes:
  - name: dev-infiniband
    hostPath:
      path: /dev/infiniband
      type: DirectoryOrCreate
  - name: hugepages
    emptyDir:
      medium: HugePages
  - name: shm
    emptyDir:
      medium: Memory
      sizeLimit: 64Gi
```

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

## Testing

On-cluster smoke harness: `tests/smoke/smoke.sh`. Every CodeBuild push should
be validated by running it against the resulting image tag.

```
cd 2.projects/dynamo-inference
./tests/smoke/smoke.sh <SHA>
```

The harness runs **10 gates** (T1–T10) against a single-pod vLLM deployment
on the H100 HyperPod cluster. Full criteria, env overrides, evidence
artifacts, and troubleshooting are documented in
[`tests/README.md`](tests/README.md).

**Blocking gates (T1–T7):** image exists in ECR, size sanity, fat-binary
NCCL with `sm_80 / sm_86 / sm_89 / sm_90 / sm_100 / sm_120`, EFA visible in
the pod, `/v1/models` returns 200, `/v1/completions` succeeds, `hw_counters`
show non-zero RDMA traffic (guards against TCP fallback).

**Warning gates (T8–T10):** no NCCL/NVLS errors in logs, SBOM present at
`/opt/security/`, pod teardown completes within 60 s.

Runs target `ml.p5.48xlarge` only (H100); P5en H200 nodes are reserved.
The harness claims `~/.claude/cluster-lock-h100.json` before deploy and
releases it via `trap` on exit.

Per-run evidence lands in `tests/out/<SHA>/` (logs, NCCL arches, hw_counters,
completion JSON, and `summary.md`).

---


---

## Reproducibility

External readers, upstream maintainers, and customer reviewers: see
[REPRODUCIBILITY.md](REPRODUCIBILITY.md) for how to build the same
images the committed `docs/evidence/` logs were produced on. You do
not need access to our private ECR or internal cluster — the
Dockerfiles pull only public NGC images, and the git commit SHAs
map 1:1 to image tags.

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

**Last Updated:** March 2026
