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
2.project/
|-- nims-inference/
|-- trtllm-inference/
|-- ray-service/ 
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


### RAY SERVICE

This repository contains some example code to help you get started with performing inference on AI/ML models on AWS accelerated EC2 instances with the help of [RayService](https://docs.ray.io/en/master/serve/index.html) (with NVIDIA GPUs).

### MULTI-NODE TRITON TRT-LLM INFERENCE

This example shows how to use K8s LeaderWorketSet for multi-node deployment of LLama 3.1 405B model across P5 instances using NVIDIA Triton and NVIDIA TRT-LLM on EKS (Amazon Elastic Kubernetes Service) with support for autoscaling. This includes instructions for installing LeaderWorkerSet, building custom image to enable features like EFA, Helm chart and associated Python script. This deployment flow uses NVIDIA TensorRT-LLM as the inference engine and NVIDIA Triton Inference Server as the model server. See multinode-triton-trtllm-inference for more information.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](https://github.com/aws-samples/awsome-inference/blob/main/LICENSE) file.

## Contributors

Thanks to all the contributors for building, reviewing and testing.

[![Contributors](https://contrib.rocks/image?repo=aws-samples/awsome-inference)](https://github.com/aws-samples/awsome-inference/graphs/contributors)
