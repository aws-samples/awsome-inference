# SGLang Configuration Library

This directory contains pre-built configurations for popular models optimized for SGLang deployment.

## Available Configurations

### Currently Available
- `deepseek-r1-distill-qwen-32b-awq.yaml` - DeepSeek R1 Distill Qwen 32B with AWQ quantization

## Using Configurations

```bash
# Deploy using a pre-built configuration
cdk deploy --config-file configs/library/deepseek-r1-distill-qwen-32b-awq.yaml

# Override specific parameters
cdk deploy --config-file configs/library/deepseek-r1-distill-qwen-32b-awq.yaml \
           --context instance_type=g6e.2xlarge \
           --context max_running_requests=10
```

When adding new configurations:
1. Test the configuration thoroughly
2. Document the model's requirements and performance characteristics
3. Include optimal SGLang parameters for the model
4. Add usage examples in the configuration comments