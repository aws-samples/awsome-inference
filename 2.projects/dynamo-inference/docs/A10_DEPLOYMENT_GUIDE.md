# A10 GPU Deployment Guide

This guide covers deploying Dynamo inference workloads on NVIDIA A10 and A10G GPUs.

## Table of Contents

- [Overview](#overview)
- [GPU Specifications](#gpu-specifications)
- [Building A10 Images](#building-a10-images)
- [Deployment Configuration](#deployment-configuration)
- [Performance Expectations](#performance-expectations)
- [Troubleshooting](#troubleshooting)

---

## Overview

The Dynamo inference platform supports NVIDIA A10/A10G GPUs for both training and inference workloads. A10 GPUs are commonly used in AWS instances (g5 family) and workshop environments.

### GPU Support Matrix

| GPU Model | CUDA Arch | Support Status | Use Case |
|-----------|-----------|----------------|----------|
| A10G | SM86 | [Completed] Supported | AWS g5 instances, workshops |
| A100 | SM80 | [Completed] Supported | High-performance inference |
| H100 | SM90 | [Completed] Supported | Production deployments |

---

## GPU Specifications

### A10 / A10G

- **GPU Memory**: 24 GB GDDR6
- **Memory Bandwidth**: 600 GB/s
- **CUDA Cores**: 9,216
- **Tensor Cores**: 288 (3rd Generation)
- **CUDA Compute Capability**: 8.6
- **TDP**: 150W (A10), 300W (A10G)

### Performance Characteristics

Compared to H100:
- ~3-4x lower memory bandwidth
- ~4-5x lower compute throughput
- Lower memory capacity (24GB vs 80GB)
- Better suited for smaller models and batch sizes

---

## Building A10 Images

### Quick Start

Build optimized images for A10 GPUs:

```bash
cd /path/to/awsome-inference/2.projects/dynamo-inference

# Set A10 architecture
export CUDA_ARCH=86
export CUDA_ARCH_NAME=A10

# Build base image
./build.sh

# Build vLLM image for A10
./build_vllm.sh

# Build TRT-LLM image for A10
./build_trtllm.sh
```

### Non-Interactive Build

For CI/CD or automated builds:

```bash
# Build all images for A10 in non-interactive mode
NON_INTERACTIVE=1 CUDA_ARCH=86 CUDA_ARCH_NAME=A10 ./build-all-runtime.sh
```

### Build Options

The build scripts support the following A10-specific options:

```bash
# Base image
CUDA_ARCH=86 \
CUDA_ARCH_NAME=A10 \
INSTALL_NCCL=1 \
INSTALL_NVSHMEM=0 \
NON_INTERACTIVE=1 \
./build.sh

# vLLM image
CUDA_ARCH=86 \
CUDA_ARCH_NAME=A10 \
NON_INTERACTIVE=1 \
./build_vllm.sh

# TRT-LLM image
CUDA_ARCH=86 \
CUDA_ARCH_NAME=A10 \
NON_INTERACTIVE=1 \
./build_trtllm.sh
```

### Image Tags

Built images will be tagged with the architecture:

```
dynamo-base-a10:latest
dynamo-vllm-a10:latest
dynamo-trtllm-a10:latest
```

---

## Deployment Configuration

### Resource Allocation

Adjust resources for A10's smaller memory:

```yaml
resources:
  requests:
    cpu: "4"
    memory: "16Gi"
    gpu: "1"
  limits:
    gpu: "1"
```

### GPU Memory Configuration

For vLLM deployments:

```yaml
extraPodSpec:
  mainContainer:
    args:
      - python3 -m dynamo.vllm
        --model-path <model-id>
        --gpu-memory-utilization 0.85  # Lower than H100 (0.9)
        --max-model-len 2048  # Reduce for larger models
```

For TRT-LLM deployments:

```yaml
extraPodSpec:
  mainContainer:
    args:
      - python3 -m dynamo.trtllm
        --model-path <model-id>
        --free-gpu-memory-fraction 0.80  # Lower than H100
        --max-seq-len 2048  # Reduce for larger models
```

### Model Selection

Recommended models for A10 GPUs (24GB memory):

| Model | Parameters | A10 Support | Notes |
|-------|-----------|-------------|-------|
| Qwen2.5-0.5B | 0.5B | [Completed] Excellent | Workshop demos |
| Qwen2.5-1.5B | 1.5B | [Completed] Good | General purpose |
| Qwen2.5-7B | 7B | [Completed] Possible | Requires optimization |
| Llama-3-8B | 8B | [Completed] Possible | Requires optimization |
| Llama-3-70B | 70B | [No] Too large | Use tensor parallelism on multiple GPUs |

### Batch Size Tuning

Reduce batch sizes for A10:

**Prefill Worker**:
```yaml
pytorch_backend_config:
  max_batch_size: 8  # Lower than H100 (16)
  max_num_tokens: 2048  # Lower than H100 (4096)
```

**Decode Worker**:
```yaml
pytorch_backend_config:
  max_batch_size: 128  # Lower than H100 (256)
  max_num_tokens: 128  # Lower than H100 (256)
```

---

## Performance Expectations

### Throughput

Expected throughput on A10 vs H100:

| Model | A10 (tok/s) | H100 (tok/s) | Ratio |
|-------|-------------|--------------|-------|
| Qwen2.5-0.5B | 150-200 | 380-470 | ~2.5x |
| Qwen2.5-1.5B | 100-150 | 250-350 | ~2.5x |
| Qwen2.5-7B | 30-50 | 100-150 | ~3x |

### Latency

Expected latency characteristics:

- **First Token Latency**: 150-250ms (vs 100-150ms on H100)
- **Per-Token Latency**: 8-12ms (vs 2-4ms on H100)
- **Batch Processing**: Better relative performance with smaller batches

### Memory Usage

Monitor memory usage carefully:

```bash
# Check GPU memory usage
kubectl exec -n dynamo-cloud <pod-name> -- nvidia-smi

# Expected memory usage for Qwen2.5-0.5B
# Model: ~2GB
# KV Cache: ~4-8GB
# Activations: ~2-4GB
# Total: ~8-14GB (out of 24GB available)
```

---

## Example Deployments

### vLLM on A10

```yaml
apiVersion: nvidia.com/v1alpha1
kind: DynamoGraphDeployment
metadata:
  name: vllm-qwen-a10
  namespace: dynamo-cloud
spec:
  services:
    Frontend:
      componentType: frontend
      dynamoNamespace: vllm-qwen-a10
      replicas: 1
      extraPodSpec:
        mainContainer:
          image: <your-registry>/dynamo-vllm-a10:latest

    VllmWorker:
      componentType: worker
      dynamoNamespace: vllm-qwen-a10
      replicas: 2
      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
          gpu: "1"
        limits:
          gpu: "1"
      extraPodSpec:
        mainContainer:
          image: <your-registry>/dynamo-vllm-a10:latest
          command: ["/bin/bash", "-c"]
          args:
            - |
              exec python3 -m dynamo.vllm \
                --model-path Qwen/Qwen2.5-0.5B-Instruct \
                --gpu-memory-utilization 0.85 \
                --max-model-len 2048
```

### TRT-LLM Disaggregated on A10

```yaml
apiVersion: nvidia.com/v1alpha1
kind: DynamoGraphDeployment
metadata:
  name: trtllm-disagg-a10
  namespace: dynamo-cloud
spec:
  services:
    Frontend:
      componentType: frontend
      dynamoNamespace: trtllm-disagg-a10
      envs:
        - name: DYN_ROUTER_MODE
          value: "kv"
      replicas: 1
      extraPodSpec:
        mainContainer:
          image: <your-registry>/dynamo-trtllm-a10:latest

    TrtllmPrefillWorker:
      componentType: worker
      subComponentType: prefill
      dynamoNamespace: trtllm-disagg-a10
      replicas: 2
      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
          gpu: "1"
        limits:
          gpu: "1"
      extraPodSpec:
        mainContainer:
          image: <your-registry>/dynamo-trtllm-a10:latest
          command: ["/bin/bash", "-c"]
          args:
            - |
              exec python3 -m dynamo.trtllm \
                --model-path Qwen/Qwen2.5-0.5B-Instruct \
                --disaggregation-mode prefill \
                --free-gpu-memory-fraction 0.80 \
                --max-seq-len 2048 \
                --extra-engine-args /config/trtllm-prefill-config-a10.yaml
          volumeMounts:
            - name: trtllm-config
              mountPath: /config
              readOnly: true
        volumes:
          - name: trtllm-config
            configMap:
              name: trtllm-config-a10

    TrtllmDecodeWorker:
      componentType: worker
      subComponentType: decode
      dynamoNamespace: trtllm-disagg-a10
      replicas: 2
      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
          gpu: "1"
        limits:
          gpu: "1"
      extraPodSpec:
        mainContainer:
          image: <your-registry>/dynamo-trtllm-a10:latest
          command: ["/bin/bash", "-c"]
          args:
            - |
              exec python3 -m dynamo.trtllm \
                --model-path Qwen/Qwen2.5-0.5B-Instruct \
                --disaggregation-mode decode \
                --free-gpu-memory-fraction 0.80 \
                --extra-engine-args /config/trtllm-decode-config-a10.yaml
          volumeMounts:
            - name: trtllm-config
              mountPath: /config
              readOnly: true
        volumes:
          - name: trtllm-config
            configMap:
              name: trtllm-config-a10
```

### A10-Specific Config Files

**trtllm-prefill-config-a10.yaml**:
```yaml
cache_transceiver_config:
  backend: DEFAULT

pytorch_backend_config:
  max_batch_size: 8  # Reduced for A10
  max_num_tokens: 2048  # Reduced for A10
  max_seq_len: 2048

  enable_chunked_context: true
  enable_trt_overlap: false
```

**trtllm-decode-config-a10.yaml**:
```yaml
cache_transceiver_config:
  backend: DEFAULT

pytorch_backend_config:
  max_batch_size: 128  # Reduced for A10
  max_num_tokens: 128  # Reduced for A10

cuda_graph_config:
  max_batch_size: 128  # Reduced for A10
  enable_cuda_graph: true
```

---

## Troubleshooting

### Out of Memory (OOM) Errors

If you encounter OOM errors on A10:

1. **Reduce GPU memory utilization**:
   ```yaml
   --gpu-memory-utilization 0.75  # Lower from 0.85
   ```

2. **Reduce max sequence length**:
   ```yaml
   --max-seq-len 1024  # Lower from 2048
   ```

3. **Reduce batch size**:
   ```yaml
   max_batch_size: 4  # Lower from 8
   ```

4. **Use a smaller model**:
   - Qwen2.5-0.5B instead of Qwen2.5-1.5B
   - Quantized models (int8, fp16)

### Performance Issues

If inference is too slow:

1. **Enable CUDA graphs** (TRT-LLM only):
   ```yaml
   cuda_graph_config:
     enable_cuda_graph: true
   ```

2. **Optimize batch sizes**:
   - Find optimal batch size through benchmarking
   - Balance latency vs throughput

3. **Reduce context length**:
   - Shorter prompts = faster inference
   - Consider prompt compression techniques

### Build Issues

If building for A10 fails:

1. **Verify CUDA architecture**:
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.1.0-devel-ubuntu22.04 nvidia-smi
   # Should show "GPU 0: A10" or similar
   ```

2. **Check CUDA compute capability**:
   ```bash
   nvidia-smi --query-gpu=compute_cap --format=csv
   # Should output: 8.6
   ```

3. **Ensure correct build args**:
   ```bash
   CUDA_ARCH=86 CUDA_ARCH_NAME=A10 ./build.sh
   ```

---

## Workshop Setup

### Quick Workshop Deployment

For workshop environments with A10 instances:

```bash
# 1. Build images for A10
NON_INTERACTIVE=1 CUDA_ARCH=86 CUDA_ARCH_NAME=A10 ./build-all-runtime.sh

# 2. Push to registry (if needed)
docker tag dynamo-vllm-a10:latest <your-registry>/dynamo-vllm-a10:latest
docker push <your-registry>/dynamo-vllm-a10:latest

# 3. Deploy demo service
kubectl apply -f deployments/vllm/vllm-qwen-a10.yaml

# 4. Test
source scripts/trtllm-helpers.sh
setup_port_forward
test_completion "Hello workshop participants!" 50
```

### Workshop Best Practices

1. **Use smaller models**: Qwen2.5-0.5B or Qwen2.5-1.5B
2. **Pre-build images**: Build before workshop to save time
3. **Monitor resources**: Use `kubectl top pods` to watch GPU usage
4. **Set conservative limits**: Better to start with lower memory/batch sizes
5. **Prepare fallbacks**: Have H100/A100 configs ready if needed

---

## AWS g5 Instance Types

A10G is available in AWS g5 instances:

| Instance Type | GPUs | GPU Memory | vCPUs | RAM | Use Case |
|--------------|------|------------|-------|-----|----------|
| g5.xlarge | 1 | 24 GB | 4 | 16 GB | Development |
| g5.2xlarge | 1 | 24 GB | 8 | 32 GB | Single model |
| g5.12xlarge | 4 | 96 GB | 48 | 192 GB | Multi-model, workshops |
| g5.48xlarge | 8 | 192 GB | 192 | 768 GB | Large scale |

### EKS Node Configuration

For A10G on EKS:

```yaml
apiVersion: eks.amazonaws.com/v1
kind: Nodegroup
metadata:
  name: gpu-a10-nodegroup
spec:
  instanceTypes:
    - g5.2xlarge  # 1x A10G
  capacityType: ON_DEMAND
  scalingConfig:
    minSize: 1
    maxSize: 4
    desiredSize: 2
  taints:
    - key: nvidia.com/gpu
      value: "true"
      effect: NoSchedule
```

---

## Additional Resources

- [NVIDIA A10 Specifications](https://www.nvidia.com/en-us/data-center/products/a10-gpu/)
- [AWS g5 Instances](https://aws.amazon.com/ec2/instance-types/g5/)
- [TensorRT-LLM Documentation](https://nvidia.github.io/TensorRT-LLM/)
- [vLLM Documentation](https://docs.vllm.ai/)

---

**Last Updated**: 2025-11-18
**Status**: Workshop Ready [Yes]
