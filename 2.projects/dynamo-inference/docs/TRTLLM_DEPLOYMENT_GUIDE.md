# TRT-LLM Deployment Guide

This guide covers deploying TensorRT-LLM (TRT-LLM) backend on Dynamo Cloud platform with disaggregated prefill/decode architecture.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration Files](#configuration-files)
- [Deployment](#deployment)
- [Testing & Validation](#testing--validation)
- [Troubleshooting](#troubleshooting)
- [Performance Benchmarks](#performance-benchmarks)

---

## Overview

TRT-LLM on Dynamo Cloud uses a disaggregated architecture that separates prefill and decode workers for optimized inference performance:

- **Prefill Workers**: Process initial prompt tokens
- **Decode Workers**: Generate completion tokens
- **Frontend**: Routes requests and manages KV cache transfer

### Architecture

```
┌─────────────┐
│  Frontend   │  (DYN_ROUTER_MODE=kv)
└──────┬──────┘
       │
   ┌───┴────┐
   │        │
┌──▼──┐  ┌─▼────┐
│Pre  │  │Decode│
│fill │  │      │
└─────┘  └──────┘
   (2x)     (2x)
```

## Prerequisites

### Cluster Requirements

- Kubernetes cluster with Dynamo Cloud platform v0.7.0+
- NVIDIA H100, A100, or A10 GPUs
- NATS messaging service (deployed via Dynamo platform)
- ETCD key-value store (deployed via Dynamo platform)

### GPU Support

| GPU Model | Support Status | Notes |
|-----------|---------------|-------|
| H100-80GB | [Completed] Tested | Production ready |
| A100-80GB | [Completed] Supported | Compatible |
| A10G | [Completed] Supported | Workshop validated |

### Container Image

Use the full image for TRT-LLM deployments:

```
<AWS_ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full
```

**Note**: The slim image has known issues with NIXL segfaults. Always use the full image (29GB).

---

## Quick Start

### 1. Deploy TRT-LLM

```bash
cd /path/to/awsome-inference/2.projects/dynamo-inference

# Create ConfigMap for TRT-LLM configurations
kubectl create configmap trtllm-config -n dynamo-cloud \
  --from-file=deployments/trtllm/trtllm-prefill-config.yaml \
  --from-file=deployments/trtllm/trtllm-decode-config.yaml

# Deploy the service
kubectl apply -f deployments/trtllm/trtllm-disagg-qwen.yaml
```

### 2. Verify Deployment

```bash
# Check pod status
kubectl get pods -n dynamo-cloud | grep trtllm

# Expected output:
# trtllm-disagg-qwen-full-frontend-*                1/1     Running
# trtllm-disagg-qwen-full-trtllmprefillworker-*     1/1     Running
# trtllm-disagg-qwen-full-trtllmprefillworker-*     1/1     Running
# trtllm-disagg-qwen-full-trtllmdecodeworker-*      1/1     Running
# trtllm-disagg-qwen-full-trtllmdecodeworker-*      1/1     Running
```

### 3. Test Inference

```bash
# Load helper functions
source scripts/trtllm-helpers.sh

# Setup port forwarding
setup_port_forward

# Run health check
test_health

# Test completion
test_completion "Hello world" 50
```

---

## Configuration Files

### Prefill Worker Configuration

**File**: `deployments/trtllm/trtllm-prefill-config.yaml`

```yaml
cache_transceiver_config:
  backend: DEFAULT  # Uses UCX for KV cache transfer

pytorch_backend_config:
  max_batch_size: 16
  max_num_tokens: 4096
  max_seq_len: 4096

  enable_chunked_context: true
  enable_trt_overlap: false
```

### Decode Worker Configuration

**File**: `deployments/trtllm/trtllm-decode-config.yaml`

```yaml
cache_transceiver_config:
  backend: DEFAULT  # Uses UCX for KV cache transfer

pytorch_backend_config:
  max_batch_size: 256
  max_num_tokens: 256

cuda_graph_config:
  max_batch_size: 256
  enable_cuda_graph: true
```

### Critical Configuration Notes

1. **cache_transceiver_config** is REQUIRED for disaggregated mode
2. Frontend must have `DYN_ROUTER_MODE=kv` environment variable
3. Config files are mounted via ConfigMap and passed with `--extra-engine-args`
4. CUDA graph configs should not set both `batch_sizes` and `max_batch_size`

---

## Deployment

### Deployment YAML Structure

The deployment uses the `DynamoGraphDeployment` CRD with three components:

#### Frontend

```yaml
Frontend:
  componentType: frontend
  dynamoNamespace: trtllm-disagg-qwen-full
  envs:
    - name: DYN_ROUTER_MODE
      value: "kv"  # CRITICAL: Enables disaggregated routing
  extraPodSpec:
    mainContainer:
      image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full
  replicas: 1
```

#### Prefill Workers

```yaml
TrtllmPrefillWorker:
  componentType: worker
  subComponentType: prefill
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
      image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full
      command: ["/bin/bash", "-c"]
      args:
        - |
          # Patch Triton Unicode bug
          TRITON_DRIVER="/opt/venv/lib/python3.12/site-packages/triton/backends/nvidia/driver.py"
          if [ -f "$TRITON_DRIVER" ]; then
            sed -i 's/subprocess\.check_output(\[.\/sbin\/ldconfig., .-p.\])\.decode()/subprocess.check_output(["\/sbin\/ldconfig", "-p"]).decode("utf-8", errors="replace")/g' "$TRITON_DRIVER"
          fi

          # Start prefill worker
          exec python3 -m dynamo.trtllm \
            --model-path Qwen/Qwen2.5-0.5B-Instruct \
            --disaggregation-mode prefill \
            --extra-engine-args /config/trtllm-prefill-config.yaml
      volumeMounts:
        - name: trtllm-config
          mountPath: /config
          readOnly: true
    volumes:
      - name: trtllm-config
        configMap:
          name: trtllm-config
```

#### Decode Workers

Similar structure to prefill workers but with:
- `subComponentType: decode`
- `--disaggregation-mode decode`
- `--extra-engine-args /config/trtllm-decode-config.yaml`

### Key Deployment Features

1. **Triton Patch**: Wrapper script fixes Unicode decoding issue
2. **Config Mounting**: ConfigMap mounts YAML configs into `/config`
3. **Environment Variables**: NATS_URL, ETCD_URL, locale settings
4. **Resource Allocation**: 1 GPU per worker, 16Gi RAM, 4 CPUs

---

## Testing & Validation

### Helper Scripts

The `scripts/trtllm-helpers.sh` provides utilities for testing:

```bash
# Source the helper functions
source scripts/trtllm-helpers.sh

# Available commands:
deploy_trtllm [yaml_file]     # Deploy service
cleanup_deployment             # Remove deployment
check_status                   # Check pod status
setup_port_forward            # Setup localhost:8000
test_health                    # Test health endpoint
test_completion [prompt] [tokens]  # Test completion API
smoke_test                     # Run full smoke test
```

### Benchmark Script

Run comprehensive benchmarks:

```bash
# Full benchmark suite
./scripts/benchmark-trtllm.sh benchmark

# Quick smoke test
./scripts/benchmark-trtllm.sh smoke

# Health check only
./scripts/benchmark-trtllm.sh health
```

### Manual Testing

```bash
# Setup port forwarding
kubectl port-forward -n dynamo-cloud svc/trtllm-disagg-qwen-full-frontend 8000:8000 &

# Health check
curl http://localhost:8000/health | jq '.'

# Test completion
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "prompt": "Hello world",
    "max_tokens": 50,
    "temperature": 0.7
  }'
```

---

## Troubleshooting

### Issue #1: KV Cache Transceiver Missing

**Error**: `AssertionError: kv_cache_transceiver is disabled`

**Solution**:
1. Ensure ConfigMap exists with both config files
2. Verify `cache_transceiver_config: backend: DEFAULT` in both configs
3. Confirm `DYN_ROUTER_MODE=kv` in Frontend environment variables
4. Check config files are mounted at `/config` in workers

### Issue #2: Triton UnicodeDecodeError

**Error**: `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xc4`

**Solution**: Wrapper script patches Triton's driver.py automatically. Ensure the patch section is present in worker args.

### Issue #3: NIXL Segfault

**Error**: Segfault in `nixlPluginManager::discoverPluginsFromDir`

**Solution**: Use full image instead of slim:
```yaml
image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full
```

### Issue #4: Argument Incompatibility

**Error**: `error: unrecognized arguments`

**Solution**: Use TRT-LLM-specific arguments:
- `--model-path` (not `--model`)
- `--disaggregation-mode prefill/decode` (not `--is-prefill-worker`)
- `--free-gpu-memory-fraction` (not `--gpu-memory-utilization`)
- `--max-seq-len` (not `--max-model-len`)

### Common Checks

```bash
# Check pod logs
kubectl logs -n dynamo-cloud <pod-name> --tail=100

# Check ConfigMap
kubectl get configmap trtllm-config -n dynamo-cloud -o yaml

# Verify DynamoGraphDeployment
kubectl get dynamographdeployment -n dynamo-cloud

# Check worker registration
curl http://localhost:8000/health | jq '.instances'
```

---

## Performance Benchmarks

### Test Configuration

- **Model**: Qwen/Qwen2.5-0.5B-Instruct
- **GPUs**: 4 × H100-80GB (2 prefill + 2 decode)
- **Date**: 2025-11-18

### Results Summary

| Test | Tokens | Duration | Throughput |
|------|--------|----------|------------|
| Short (50) | 50 | 0.131s | 381 tok/s |
| Short (150) | 150 | 0.322s | 465 tok/s |
| Medium (100) | 100 | 0.213s | 470 tok/s |
| Long (50) | 50 | 0.129s | 387 tok/s |
| Latency (avg) | - | 0.126s | - |

### Key Metrics

- **Average Latency**: 126ms
- **Throughput Range**: 381-470 tokens/sec
- **Startup Time**: ~90 seconds (includes model loading)
- **Pod Stability**: 0 restarts, 100% uptime

Full benchmark results: `benchmark-results/trtllm_benchmark_20251118_191302.md`

---

## Additional Resources

- [Dynamo Cloud Documentation](https://docs.nvidia.com/dynamo)
- [TensorRT-LLM Documentation](https://nvidia.github.io/TensorRT-LLM/)
- [Complete Test Guide](COMPLETE_TEST_GUIDE.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Development History](DEVELOPMENT_HISTORY.md)

---

## Configuration Reference

### TRT-LLM Command Arguments

```bash
python3 -m dynamo.trtllm \
  --model-path <hf-model-id> \
  --disaggregation-mode {prefill|decode} \
  --free-gpu-memory-fraction 0.8 \
  --max-seq-len 4096 \
  --extra-engine-args /config/trtllm-{prefill|decode}-config.yaml
```

### Environment Variables

Required for workers:
- `NATS_URL`: NATS messaging endpoint
- `ETCD_URL`: ETCD key-value store endpoint
- `LC_ALL=C.UTF-8`: Locale setting
- `LANG=C.UTF-8`: Language setting
- `PYTHONIOENCODING=utf-8`: Python encoding

Required for frontend:
- `DYN_ROUTER_MODE=kv`: Enable disaggregated routing

---

**Last Updated**: 2025-11-18
**Status**: Production Ready [Yes]
