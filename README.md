## ML Inference Reference Architectures & Tests

This repository contains reference architectures and test cases for inference with [Amazon Elastic Kubernetes Service](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html), [AWS Accelerated EC2 Instances](https://aws.amazon.com/ec2/instance-types/), (more coming soon). These examples and test cases cover a variety of models and uses cases, as well as frameworks for optimization (such as examples of using NVIDIA TensorRT-LLM).

The goal of this repository is to provide you with end-to-end setups for optimizing inference solutions on AWS.

Note: This repository will continue to get updated with more use cases, examples, and architectures of performing inference on AWS.

The major components of this directory are:
```bash
README                                # Project Summaries
1.infrastructure/
|-- README                            # Setup for infrastructure (VPC, EKS cluster etc)
|-- 0_setup_vpc/                      # CloudFormation templates for reference VPC
|-- 1_setup_cluster/                  # Scripts to create your cluster using EKS
2.projects/
|-- nims-inference/
|-- trtllm-inference/
|-- sglang-inference/
|-- ray-service/ 
|-- multinode-triton-trtllm-inference/
|-- mixture-of-agents/
|-- neuronx-distributed/
|-- mig-gpu-partitioning/
3.use-cases/
|-- nims-inference/
`-- ...
// Other directories
```

## Infrastructure

This directory consists of examples and templates for you to set up your infrastructure on AWS for inference. It consists of setups for a VPC (and related components), along with a detailed setup of your cluster. Please check out this directory to create your infrastructure on AWS before proceeding to `2.project/`, where you can find inference specific framework setups.

## Projects

### NIMS-INFERENCE

This project aims to reduce the effort required to set up optimized inference workloads on AWS, with the help of NVIDIA NIMs. NIMs provides users with an efficient optimization framework that is very quick and easy to set up. The example shown demonstrates running the Llama3-8B model on P5 instances and scaling with Amazon Elastic Kubernetes Service (EKS). See [nims-inference](https://github.com/aws-samples/awsome-inference/blob/main/2.projects/nims-inference/README.md) for more information.

### TRTLLM-INFERENCE

This project aims at optimizing inference on GPU based AWS Accelerated Computing instances by demonstrating an example of running the Llama3-8B model on P5 instances and optimizing inference using NVIDIA's TensorRT-LLM. Scaling is demonstrated using Amazon Elastic Kubernetes Service (EKS).
See [trtllm-inference](https://github.com/aws-samples/awsome-inference/blob/main/2.projects/trtllm-inference/README.md) for more information.

### SGLANG-INFERENCE

This project provides a CDK-based deployment of [SGLang](https://github.com/sgl-project/sglang), a high-performance LLM serving framework, on AWS infrastructure. It features auto-scaling GPU workers, pre-built AMIs for fast startup, and a load-balancing router. The solution supports various quantization methods and is optimized for high-throughput, cost-effective deployments on EC2 instances (G4dn, G5, G6, P4d, P5).
See [sglang-inference](https://github.com/aws-samples/awsome-inference/blob/main/2.projects/sglang-inference/README.md) for more information.

### RAY SERVICE

This repository contains some example code to help you get started with performing inference on AI/ML models on AWS accelerated EC2 instances with the help of [RayService](https://docs.ray.io/en/master/serve/index.html) (with NVIDIA GPUs).

### MULTI-NODE TRITON TRT-LLM INFERENCE

This example shows how to use [K8s LeaderWorketSet](https://github.com/kubernetes-sigs/lws/tree/main) for multi-node deployment of LLama 3.1 405B model across P5 (H100) instances using NVIDIA Triton and NVIDIA TRT-LLM on EKS (Amazon Elastic Kubernetes Service) with support for autoscaling. This includes instructions for installing LeaderWorkerSet, building custom image to enable features like EFA, Helm chart and associated Python script. This deployment flow uses NVIDIA TensorRT-LLM as the inference engine and NVIDIA Triton Inference Server as the model server. This example should also work for other GPU instances like G5, P4D, G6, G6E, P5E. See [multinode-triton-trtllm-inference](2.projects/multinode-triton-trtllm-inference) for more information.


### MIXTURE OF AGENTS (MoA)

Recent advances in large language models (LLMs) have shown substantial capabilities, but harnessing the collective expertise of multiple LLMs is an open direction. [Mixture-of-Agents (MoA)](https://github.com/togethercomputer/MoA) approach to leverages the collective strengths of multiple LLMs through a layered architecture. Each layer comprises multiple LLMs, and each model uses outputs from the previous layer's agents as auxiliary information. See [Mixture-of-Agents (MoA) on Amazon bedrock](/2.projects/mixture-of-agents) for more information.

### TRITON TRT-LLM SAGEMAKER

These examples shows how to deploy LLMs like T5, Mistral using NVIDIA Triton TRT-LLM on Amazon SageMaker. See [triton-trtllm-sagemaker](2.projects/triton-trtllm-sagemaker) for more information.

### NEURONX DISTRIBUTED INFERENCE - FUSED SPECULATIVE DECODING on EKS

This project demonstrates deploying Large Language Models using **NeuronX Distributed Inference (NxDI)** with **vLLM-Neuron** on Amazon EKS with AWS Trainium instances (trn1.32xlarge). The solution showcases advanced inference optimization techniques including **fused draft speculative decoding**.

**Key Technical Features:**
- **Fused Speculative Decoding**: Combines target model (e.g., Qwen3-32B) with draft model (e.g., Qwen3-0.6B) for accelerated token generation with maintained quality
- **Kubernetes-Native Architecture**: Separate jobs for model download, compilation (spec/non-spec), and inference deployment with shared EFS storage
- **Advanced Monitoring**: Neuron Monitor DaemonSet with Prometheus, Grafana, and CloudWatch integration for comprehensive observability
- **Flexible Configuration**: Easy toggling between speculative and standard inference modes with configurable parameters

The architecture features isolated artifact storage (no overwrites between spec/non-spec modes), tensor parallelism optimization (TP=32), and comprehensive performance monitoring including NeuronCore utilization, inference latency, and throughput metrics. See [neuronx-distributed/nxd-inference-eks](2.projects/neuronx-distributed/nxd-inference-eks) for more information.

### NEURONX DISTRIBUTED INFERENCE - Profiling and Benchmarking Guide

This example on EC2 walks through deploying, profiling, and benchmarking LLMs on EC2 with NxDI. See [neuronx-distributed/nxd-inference-ec2](2.projects/neuronx-distributed/nxdi-ec2-vllm) for more information.

### MIG 

This directory contains a README on how you can leverage Multi-Instance GPUs (MIGs) to partition your GPUs based on your workload. For more detailed documentation, check out the [MIG user guide](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/).

## USE-CASES
These are real life use-case examples on using projects from `2.PROJECTS/` to demonstrate catering the projects to real-life scenarios.

### AUDIO BOT

This repository contains an example of how to build an audio bot using EC2 with NIMs.  This will deploy an EC2 instance with NIMs installed and configured to support ASR, Inference, and TTS.  The bot will run on an EC2 instance and will be able to receive audio input from a user and respond with audio output.  See [audio-bot](https://github.com/aws-samples/awsome-inference/audio-bot/blob/main/3.use-cases/nims-inference/audio-bot/README.md) for more information.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](https://github.com/aws-samples/awsome-inference/blob/main/LICENSE) file.

## Contributors

Thanks to all the contributors for building, reviewing and testing.

[![Contributors](https://contrib.rocks/image?repo=aws-samples/awsome-inference)](https://github.com/aws-samples/awsome-inference/graphs/contributors)

## Star History
[![Star History Chart](https://api.star-history.com/svg?repos=aws-samples/awsome-inference&type=Date)](https://star-history.com/#aws-samples/awsome-awsome-inference&Date)

