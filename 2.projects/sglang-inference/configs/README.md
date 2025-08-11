# SGLang Configuration System

This directory contains configuration files for deploying SGLang with AWS CDK. The configuration system allows you to define model, instance, and SGLang parameters in a structured YAML format.

## Overview

The configuration system provides a hierarchical structure for defining:
- **Model Configuration** - Hugging Face model ID and revision
- **Instance Configuration** - EC2 instance types and scaling parameters
- **SGLang Parameters** - All SGLang runtime arguments

## Directory Structure

```
configs/
├── schema/          # JSON Schema for configuration validation
├── examples/        # Example configurations to get started
└── library/         # Pre-built configurations for common models
```

## Configuration File Format

Configuration files use YAML format with the following structure:

```yaml
version: "1.0"
metadata:
  name: "configuration-name"
  description: "Description of this configuration"

model:
  id: "hugging-face/model-id"
  revision: "main"  # optional

instances:
  workers:
    type: "g6e.xlarge"
    min_capacity: 1
    max_capacity: 3
    desired_capacity: 1
  router:
    type: "t3.medium"  # optional
    ip: "10.0.0.100"   # optional

sglang:
  # SGLang runtime parameters (all optional)
  quantization: "awq_marlin"
  kv_cache_dtype: "fp8_e5m2"
  # ... additional parameters
```

## Usage

### Using a Configuration File

```bash
cdk deploy --context config_file=configs/library/openai/gpt-oss-120b/g6e-12xlarge.yaml
```

### Overriding Configuration Values

You can override specific values from the configuration file using CDK context parameters:

```bash
# Override instance type
cdk deploy --context config_file=configs/library/openai/gpt-oss-120b/g6e-12xlarge.yaml \
           --context instance_type=g6e.2xlarge

# Override multiple parameters
cdk deploy --context config_file=configs/examples/basic-config.yaml \
           --context model_id=Valdemardi/DeepSeek-R1-Distill-Qwen-32B-AWQ \
           --context instance_type=g6e.xlarge \
           --context max_capacity=5

# Override SGLang parameters
cdk deploy --context config_file=configs/library/openai/gpt-oss-120b/g6e-12xlarge.yaml \
           --context quantization=awq_marlin \
           --context kv_cache_dtype=fp8_e5m2 \
           --context mem_fraction_static=0.85
```

### Traditional Usage (Backward Compatible)

The traditional method of passing parameters still works:

```bash
cdk deploy --context model_id=Valdemardi/DeepSeek-R1-Distill-Qwen-32B-AWQ \
           --context instance_type=g6e.xlarge
```

## Configuration Priority

When multiple configuration sources are present, they are applied in this order (highest to lowest priority):
1. Environment variables (highest priority)
2. CDK context parameters (`--context` flags override file values)
3. Configuration file values (base configuration)
4. System defaults (lowest priority)

For example, if you specify `instance_type` in both the config file and via `--context`, the context value will be used.

## Available SGLang Parameters

The `sglang` section supports all SGLang runtime parameters including:

- **Quantization**: `quantization`, `quantization_param_path`
- **Memory**: `mem_fraction_static`, `kv_cache_dtype`, `dtype`
- **Performance**: `tensor_parallel_size`, `enable_torch_compile`, `cuda_graph_max_bs`
- **Context**: `context_length`, `max_total_tokens`, `max_prefill_tokens`
- **Scheduling**: `schedule_policy`, `max_running_requests`
- **And many more...**

See the schema file for a complete list of supported parameters.

## Creating Custom Configurations

1. Start with an example from `examples/` directory
2. Modify the parameters for your use case
3. Save with a descriptive name (e.g., `configs/my-custom-config.yaml`)
4. Validate against the schema (optional but recommended)

### Example Custom Configuration

Create a file `configs/my-llama-config.yaml`:

```yaml
version: "1.0"
metadata:
  name: "llama-optimized"
  description: "Optimized configuration for Llama models"

model:
  id: "hugging-quants/Meta-Llama-3.1-8B-Instruct-AWQ-INT4"

instances:
  workers:
    type: "g6e.xlarge"
    min_capacity: 2
    max_capacity: 10
    desired_capacity: 3
  router:
    ip: "10.0.0.150"

sglang:
  quantization: "awq_marlin"
  kv_cache_dtype: "fp8_e5m2"
  mem_fraction_static: 0.90
  context_length: 32768
  tensor_parallel_size: 1
```

Deploy with optional overrides:

```bash
cdk deploy --context config_file=configs/my-llama-config.yaml \
           --context desired_capacity=5
```

## Future Extensions

The configuration system is designed to support future features including:
- Disaggregated prefill/decode configurations
- Multi-instance serving specifications
- Advanced networking configurations