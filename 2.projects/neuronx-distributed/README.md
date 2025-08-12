# NeuronX Distributed Inference on AWS

This directory contains examples for deploying Large Language Models using **NeuronX Distributed Inference (NxDI)** on AWS Trainium instances. NxDI is an open-source PyTorch-based inference library that simplifies deep learning model deployment on AWS Inferentia and Trainium instances, offering advanced inference capabilities including continuous batching and speculative decoding.

## What is NeuronX Distributed Inference?

[NeuronX Distributed Inference](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/nxd-inference/nxdi-overview.html) (NxDI) is introduced with Neuron SDK 2.21+ and provides high-performance inference on AWS Trainium and Inferentia instances with features like continuous batching, speculative decoding, and seamless vLLM integration for production deployments.

## Examples

This directory contains two deployment approaches for different use cases:

### 1. EKS Deployment (`nxd-inference-eks/`)

**Production-ready, scalable Kubernetes deployment**

- **Use Case**: Enterprise production workloads requiring high availability, auto-scaling, and load balancing
- **Models**: Llama 3.3 70B, DeepSeek-R1-Distill-Llama-70B, and other large language models
- **Instance Types**: `trn1.32xlarge`, `trn2.48xlarge`
- **Key Features**:
  - Kubernetes-native deployment with HPA/VPA scaling
  - EFS shared storage for model artifacts
  - Neuron monitoring and observability
  - Support for standard and speculative decoding modes
  - Load balancing with AWS Application Load Balancer

**[→ See EKS Deployment Guide](nxd-inference-eks/README.md)**

### 2. EC2 Deployment (`nxdi-ec2-vllm/`)

**Direct EC2 deployment for development and testing**

- **Use Case**: Development, experimentation, and simpler production setups
- **Models**: Mistral Small 24B (primary example) and other NxDI-compatible models
- **Instance Types**: `trn1.32xlarge`
- **Key Features**:
  - Jupyter notebook-based setup and experimentation
  - Direct vLLM integration
  - Performance benchmarking tools (`llmperf`, `lm_eval`)
  - Profiling and optimization capabilities

**[→ See EC2 Deployment Guide](nxdi-ec2-vllm/README.md)**

## Choosing the Right Deployment

| Requirement | EKS Deployment | EC2 Deployment |
|-------------|----------------|----------------|
| **Production workloads** | ✅ Recommended | ⚠️ Limited scalability |
| **Development/Testing** | ⚠️ Complex setup | ✅ Recommended |
| **Auto-scaling** | ✅ HPA/VPA support | ❌ Manual scaling |
| **High availability** | ✅ Multi-AZ support | ❌ Single instance |
| **Setup complexity** | ⚠️ Moderate | ✅ Simple |
| **Cost optimization** | ✅ Scale to zero | ❌ Always running |

## Prerequisites

Before using either example, ensure you have:

1. **AWS Account** with appropriate permissions for Trainium instances
2. **VPC Setup**: Use the provided template in [`1.infrastructure/0_setup_vpc/trn-vpc-example.yaml`](../../1.infrastructure/0_setup_vpc/trn-vpc-example.yaml)
3. **Instance Quotas**: Sufficient quota for Trainium instances in your target region
4. **HuggingFace Token**: For downloading gated models (Llama, etc.)

## Getting Started

1. **Choose your deployment approach** based on your use case
2. **Set up the prerequisite infrastructure** (VPC, quotas)
3. **Follow the specific README** for your chosen deployment method
4. **Configure your models and parameters** according to your requirements

## Performance Characteristics

Both examples demonstrate high-performance inference capabilities:

- **Throughput**: Up to 100+ tokens/second for 70B models on `trn1.32xlarge`
- **Latency**: Sub-second time-to-first-token with speculative decoding
- **Efficiency**: Optimized memory usage with tensor parallelism
- **Scalability**: Horizontal scaling (EKS) or vertical optimization (EC2)

## Support and Resources

- [AWS Neuron Documentation](https://awsdocs-neuron.readthedocs-hosted.com/)
- [NeuronX Distributed Inference Guide](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/nxd-inference/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [AWS Trainium Developer Guide](https://docs.aws.amazon.com/dlami/latest/devguide/tutorial-inferentia.html)