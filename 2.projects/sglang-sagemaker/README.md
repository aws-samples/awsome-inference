# SGLang on Amazon SageMaker

This project demonstrates how to deploy large language models on Amazon SageMaker using [SGLang](https://github.com/sgl-project/sglang), a high-performance LLM serving framework. SGLang provides efficient multi-request scheduling, continuous batching, and distributed inference capabilities, making it ideal for high-throughput production deployments.

## Overview

SGLang (Structured Generation Language) is a fast serving framework for large language models and vision language models. When deployed on SageMaker, it provides:

- **High-throughput inference** with continuous batching and Radix Attention
- **OpenAI-compatible API** for easy integration with existing tools
- **Distributed inference** with tensor parallelism across multiple GPUs
- **Managed infrastructure** with SageMaker's scaling and monitoring capabilities

## Architecture

The solution consists of:

1. **Model Storage**: Download models from Hugging Face and store in your S3 bucket
2. **Container Image**: Build SageMaker-compatible SGLang container using the official Dockerfile
3. **SageMaker Endpoint**: Deploy on multi-GPU instances (e.g., ml.p5.48xlarge with 8x H100 GPUs)
4. **API Interface**: OpenAI-compatible chat completions API

## Features

### SGLang Optimizations
- **Continuous Batching**: Efficient request scheduling to maximize GPU utilization
- **Radix Attention**: Advanced attention mechanism for improved performance
- **Tensor Parallelism**: Distribute large models across multiple GPUs
- **Chunked Prefill**: Configurable prefill chunking for latency/throughput trade-offs
- **KV Cache Management**: Optimized memory usage for long sequences

### SageMaker Integration
- **Managed Endpoints**: Auto-scaling, health monitoring, and managed infrastructure
- **Security**: VPC support, IAM roles, and encryption at rest/in transit
- **Monitoring**: CloudWatch metrics and logging integration
- **Multi-AZ**: High availability across availability zones

## Prerequisites

- AWS account with ECR, S3, and SageMaker permissions
- Docker environment for building containers
- Hugging Face token (for gated models)
- Sufficient quota for GPU instances (P4d, P5, G5, etc.)
- S3 bucket for model storage

## References

- [SGLang GitHub Repository](https://github.com/sgl-project/sglang)
- [SGLang Documentation](https://sgl-project.github.io/sglang/)
- [Amazon SageMaker Developer Guide](https://docs.aws.amazon.com/sagemaker/)
- [Qwen Model Family](https://huggingface.co/Qwen)

## License

This project is licensed under the MIT-0 License. See the [LICENSE](../../LICENSE) file for details.