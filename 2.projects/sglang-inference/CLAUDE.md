# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an AWS CDK application that deploys SGLang (a high-performance LLM serving framework) on AWS infrastructure. It creates a distributed inference system with auto-scaling GPU workers and a prompt cache aware load-balancing router.

## Common Commands

### Setup and Deployment

```bash
# Navigate to project directory (from awsome-inference root)
cd 2.projects/sglang-inference

# Setup virtual environment
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Deploy with default model (DeepSeek-R1-Distill-Qwen-32B-AWQ)
cdk deploy

# Deploy with specific model and instance type
cdk deploy --context model_id=hugging-quants/Meta-Llama-3.1-8B-Instruct-AWQ-INT4 --context instance_type=g6e.xlarge

# Deploy with additional SGLang parameters
cdk deploy --context model_id=<model> --context instance_type=<type> --context quantization=awq_marlin --context kv_cache_dtype=fp8_e5m2
```

### CDK Commands
- `cdk ls` - List all stacks
- `cdk synth` - Synthesize CloudFormation template
- `cdk diff` - Compare with deployed stack
- `cdk destroy` - Tear down the stack

### Testing
```bash
# Run unit tests
pytest tests/unit/test_cdk_stack.py

# Run benchmarks (after deployment)
export OPENAI_API_BASE="http://<router-ip>:8000/v1"
export OPENAI_API_KEY="None"
python3 tests/token_benchmark_ray.py --model "<model-name>" --num-concurrent-requests 5
```

## Architecture

The system consists of:

1. **VPC** (`cdk/vpc.py`) - Network isolation for all resources
2. **ImageBuilder** (`cdk/image_builder.py`) - Creates AMIs with pre-installed models
3. **Router** (`cdk/router.py`) - Single EC2 instance for load balancing (default IP: 10.0.0.100:8000, configurable via context)
4. **Workers** (`cdk/workers.py`) - Auto Scaling Group of GPU instances running SGLang servers
5. **Logging** (`cdk/logs.py`) - CloudWatch integration

### Key Design Patterns

- **Pre-built AMIs**: Models are downloaded during AMI creation for fast worker startup
- **Auto-scaling**: Workers scale based on load with warm pools enabled
- **Service Discovery**: Router discovers workers via AWS APIs
- **Health Monitoring**: Automatic health checks and restarts

### Model Storage
- Models downloaded to: `/opt/sglang/models/{model_name}`
- Torch cache: `/opt/sglang/torch_compile_cache/`
- Logs: `/opt/sglang/logs/sglang.log`

### Supported Instance Types
- G4dn, G5, G5g, G6, G6e (default), GR6, P4d, P5

### Key SGLang Parameters (via CDK context)
- `quantization`: Model quantization method (awq, awq_marlin, etc.)
- `tensor_parallel_size`: Multi-GPU tensor parallelism
- `mem_fraction_static`: GPU memory allocation
- `context_length`: Maximum context length
- `kv_cache_dtype`: KV cache data type