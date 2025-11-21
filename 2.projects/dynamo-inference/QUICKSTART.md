# Quick Start Guide

## Prerequisites
- Kubernetes cluster with GPU nodes
- kubectl configured
- Docker (optional)

## One-Command Setup

```bash
# Complete setup with HuggingFace token
HF_TOKEN=your_token_here ./scripts/quick-start.sh

# Or without HuggingFace token
./scripts/quick-start.sh
```

## What It Does

1. **Setup** - Creates namespace, secrets, deploys ETCD
2. **Configure** - Auto-detects environment, replaces hardcoded values
3. **Validate** - Checks all prerequisites and deployment health

## Manual Steps

If you prefer to run each step separately:

```bash
# 1. Initial setup
HF_TOKEN=your_token ./scripts/setup-all.sh

# 2. Configure environment
./scripts/configure-environment.sh

# 3. Validate deployment
./scripts/validate-deployment.sh
```

## Build and Deploy

```bash
# Build Docker images
./docker/build.sh

# Deploy vLLM
./scripts/deploy-dynamo-vllm.sh

# Run benchmarks
./benchmarks/vllm-genai-perf/master-benchmark.sh
```

## Key Features

- **Non-Interactive**: All scripts use environment variables
- **Auto-Detection**: Automatically finds ETCD, GPUs, and cluster resources
- **Placeholder Support**: No hardcoded AWS accounts or IPs
- **Comprehensive Validation**: 12-point health check system

## Environment Variables

```bash
# Core configuration
export NAMESPACE=dynamo-cloud
export CONTAINER_REGISTRY=public.ecr.aws
export AWS_ACCOUNT_ID=YOUR_ACCOUNT_ID
export AWS_REGION=us-east-2
export HF_TOKEN=your_huggingface_token

# Skip options (all default to false)
export SKIP_OPERATOR_CHECK=true
export SKIP_ETCD=true
export SKIP_DOCKER_PULL=true
```

## Troubleshooting

Run validation to identify issues:
```bash
./scripts/validate-deployment.sh
```

View the generated report:
```bash
cat /tmp/validation-report-*.txt
```

## Fixed Issues

- **nixlbench ETCD validation**: Fixed with environment variable bypass
- **Hardcoded values**: Replaced with placeholders
- **Interactive prompts**: Removed, all configuration via environment

## Next Steps

After successful setup:
1. Build your Docker images
2. Deploy models (vLLM or TRT-LLM)
3. Run performance benchmarks
4. View results in benchmark reports