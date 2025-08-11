# SGLang on AWS CDK

Deploy [SGLang](https://github.com/sgl-project/sglang), a high-performance LLM serving framework, on AWS infrastructure using AWS CDK.

## Overview

This project provides a CDK application that deploys a distributed inference system with:

- **Auto-scaling GPU workers** running SGLang inference servers
- **Load-balancing router** that distributes requests across workers
- **Pre-built AMIs** with models downloaded for fast startup times
- **CloudWatch integration** for monitoring and logging
- **Warm pools** for rapid scaling

## Architecture

```
                    ┌─────────────┐
                    │   Router    │
                    │ (10.0.0.100)│
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────▼────┐       ┌────▼────┐       ┌────▼────┐
   │ Worker  │       │ Worker  │       │ Worker  │
   │  GPU    │       │  GPU    │  ...  │  GPU    │
   └─────────┘       └─────────┘       └─────────┘
   Auto Scaling Group (scales based on load)
```

## Prerequisites

- AWS Account with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Python 3.8+ installed
- AWS CLI configured with credentials

## Quick Start

1. **Navigate to project and setup:**
   ```bash
   # From the awsome-inference root directory
   cd 2.projects/sglang-inference
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Deploy with default model:**
   ```bash
   # Option 1: Deploy with default DeepSeek model
   cdk deploy
   ```
   This deploys DeepSeek-R1-Distill-Qwen-32B-AWQ on g6e.xlarge instances.

   **Or deploy with OpenAI GPT model:**
   ```bash
   # Option 2: Deploy using OpenAI GPT-OSS-20B configuration
   cdk deploy --context config_file=configs/examples/basic-config.yaml
   ```
   This deploys OpenAI's GPT-OSS-20B model on g6e.xlarge instances.

## Configuration

### Configuration File System (Recommended)

The project now supports YAML configuration files for easier deployment management:

```bash
# Deploy using the OpenAI GPT example configuration
cdk deploy --context config_file=configs/examples/basic-config.yaml

# Deploy using a pre-built library configuration
cdk deploy --context config_file=configs/library/openai/gpt-oss-120b/g6e-12xlarge.yaml

# Override specific parameters
cdk deploy --context config_file=configs/examples/basic-config.yaml \
           --context instance_type=g6e.2xlarge \
           --context max_capacity=5
```

See the [Configuration Documentation](configs/README.md) for detailed information about the configuration system.

### CDK Context Parameters (Traditional Method)

- `model_id`: Hugging Face model ID (default: Valdemardi/DeepSeek-R1-Distill-Qwen-32B-AWQ)
- `instance_type`: EC2 instance type (default: g6e.xlarge)
- `router_ip`: Router private IP (default: 10.0.0.100)
- Plus all SGLang parameters (quantization, kv_cache_dtype, etc.)

Example with SGLang parameters:
```bash
cdk deploy --context model_id=<model> \
           --context quantization=awq_marlin \
           --context kv_cache_dtype=fp8_e5m2 \
           --context tensor_parallel_size=2
```

## Testing

After deployment, get the router's public IP from the AWS Console and test:

```bash
export OPENAI_API_BASE="http://<router-public-ip>:8000/v1"
export OPENAI_API_KEY="None"

# Test with OpenAI client
python3 tests/test_oai.py

# Run benchmarks
python3 tests/stress_test.py
```

## Clean Up

Remove all resources:
```bash
cdk destroy
```

## Troubleshooting

1. **Workers not starting:** Check CloudWatch logs at `/aws/ec2/sglang`
2. **Router not accessible:** Verify security groups allow port 8000
3. **Model download fails:** Ensure instance has internet access and sufficient disk space

## Related Projects

For other inference deployment options in this repository, see:
- [NIMS-INFERENCE](../nims-inference/README.md) - NVIDIA NIMs on EKS/EC2/SageMaker
- [TRTLLM-INFERENCE](../trtllm-inference/README.md) - TensorRT-LLM optimization on EKS
- [Ray Service](../ray-service/README.md) - Ray-based model serving on EKS

## Infrastructure Setup

Before deploying SGLang, ensure you have the necessary AWS infrastructure:
- See [Infrastructure Setup](../../1.infrastructure/README.md) for VPC and networking setup
- SGLang can use existing VPCs or create new ones automatically

## Contributing

Please read our contributing guidelines before submitting pull requests.

## Running Integration Tests

After deploying the SGLang cluster, you can run integration tests to verify the deployment is working correctly.

### Prerequisites

Install test dependencies:
```bash
pip install -r requirements-dev.txt
```

### Running Tests

The integration tests will automatically discover the router instance by looking for an EC2 instance with private IP `10.0.0.100`. Alternatively, you can specify the router IP directly:

```bash
# Automatic discovery
pytest tests/integration/test_cluster.py -v

# Specify router IP manually
export SGLANG_ROUTER_IP=<your-router-public-ip>
pytest tests/integration/test_cluster.py -v

# Specify a different model name (if you deployed with a custom model)
export SGLANG_MODEL_NAME=<your-model-name>
pytest tests/integration/test_cluster.py -v
```

### Test Coverage

The integration tests verify:
- Router connectivity and health
- OpenAI API compatibility
- Chat completion requests (both regular and streaming)
- Concurrent request handling
- Error handling for invalid inputs
- Token usage tracking
- Context length handling

### Running Specific Tests

```bash
# Run only connectivity tests
pytest tests/integration/test_cluster.py::TestSGLangCluster::test_router_connectivity -v

# Run with timeout
pytest tests/integration/test_cluster.py -v --timeout=300
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
