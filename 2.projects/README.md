## Projects

Once you have your infrastructure set up, your next step is to choose your inference solution. This sub-directory consists of example end-to-end implementations of different inference optimization frameworks on AWS.

The major components of this directory are:
```bash
|-- nims-inference/                      
|-- trtllm-inference/ 
|-- sglang-inference/
|-- ray-service/                
|-- multinode-triton-trtllm-inference/
|-- mixture-of-agents/
`-- ...
// Other directories
```

## TRTLLM-INFERENCE

This project aims at optimizing inference on GPU based AWS Accelerated Computing instances by demonstrating an example of running the Llama3-8B model on P5 instances and optimizing inference using NVIDIA's TensorRT-LLM. Scaling is demonstrated using Amazon Elastic Kubernetes Service (EKS).
See [trtllm-inference](https://github.com/aws-samples/awsome-inference/blob/main/trtllm-inference/README.md) for more information.

### Files & Directories
1. `2.setup_container/`: This directory contains a `Dockerfile` (that you can edit, as needed, to build), a script `ecr-secret` that sets up an ecr secret for you to push images into a private ecr repo, a `healthcheck.py` script that sets up a simple http server on port `8080` of your pods, an `ingress.yaml` file that sets up an Application Load Balancer for your pods, a `manifest.yaml` file that consists of the pod deployment definition, along with a NodePort Service definition, and a `requirements.txt` file that consists of additional packages required for your pods to run TensorRT-LLM.
2. `3.within_container/`: This directory consists of scripts that run within your pods/containers. `1.install_git_and_gitlfs_and_others.sh` and `2.install_trtllm_and_triton.sh` are self-explanatory, and run during the `docker build` process. `3.local_inference.sh` consists of all the optimizations you make to TensorRT-LLM while building out the inference optimized engine (i.e., you can make changes to this script before running `docker build`), and is run as an `ENTRYPOINT` to the pod.
3. `frontend/`: Consists of some sample code to set up a frontend for serving inference requests.
4. `Images/`: Consists of architecture diagrams and other images used by the `trtllm-inference` directory.

## NIMS-INFERENCE

This project aims to reduce the effort required to set up optimized inference workloads on AWS, with the help of NVIDIA NIMs. NIMs provides users with an efficient optimization framework that is very quick and easy to set up. The example shown demonstrates running the Llama3-8B model on P5 instances and scaling with Amazon Elastic Kubernetes Service (EKS). See [nims-inference](https://github.com/aws-samples/awsome-inference/blob/main/nims-inference/README.md) for more information.

### Files & Directories
1. `benchmark/`: This directory consists of all the performance testing numbers for NIM. This directory also consists of example benchmarking scripts that you can use as-is, or with additional flags as defined by NVIDIA's `genai-perf` tool.
2. `ec2-deployment/`: This directory consists of all the deployment files needed to get started with deploying NIM on EC2
3. `nim-on-sagemaker/`: This directory consists of all the deployment files and example plug-and-play notebooks needed to get started with deploying NIM on SageMaker
4. `nim-deploy/`: This directory, provided by NVIDIA, contains helm charts and templates to get inference with NIMs set up quickly and efficiently.

## SGLANG-INFERENCE

This project provides a complete AWS CDK solution for deploying [SGLang](https://github.com/sgl-project/sglang), a high-performance LLM serving framework. Unlike the Kubernetes-based deployments above, this uses native EC2 Auto Scaling Groups with pre-built AMIs for rapid scaling. The solution includes automated model downloading during AMI creation, warm pools for fast instance startup, and CloudWatch integration for monitoring. It's particularly well-suited for high-throughput inference workloads requiring cost optimization and rapid scaling. See [sglang-inference](https://github.com/aws-samples/awsome-inference/blob/main/2.projects/sglang-inference/README.md) for more information.

### Files & Directories
1. `cdk/`: AWS CDK infrastructure code including VPC, router, workers, and auto-scaling configuration
2. `src/`: Runtime scripts for router and worker services, monitoring, and configuration
3. `tests/`: Integration and performance testing scripts, including OpenAI API compatibility tests
4. `app.py`: Main CDK application entry point
5. Model support includes various quantization methods (AWQ, AWQ-Marlin, FP8) and tensor parallelism

## RAY-SERVICE

[RayService](https://docs.ray.io/en/latest/serve/index.html) is a scalable model serving library for building online inference APIs. Ray Serve is a flexible toolkit for deploying various models, including deep learning, Scikit-Learn, and custom Python logic. Built on Ray, it scales across multiple machines and offers flexible resource allocation, enabling efficient, cost-effective model deployment. This repo contains an example to be able to run [StableDiffusion](https://huggingface.co/stabilityai/stable-diffusion-2), [MobileNet](https://arxiv.org/abs/1801.04381), and [DETR](https://huggingface.co/docs/transformers/en/model_doc/detr) models on AWS and scale using [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).
</p>

### Files & Directories
1. `MobileNet/`: This directory contains a Ray Service yaml and python code to run inference for this image classification model.
2. `StableDiffusion/`: This directory contains a Ray Service yaml and python code to run inference for this text-to-image model. 
3. `DETR/`: This directory contains a Ray Service yaml and python code to run inference for this object detection model.


## MULTI-NODE TRITON TRT-LLM INFERENCE

This example shows how to use K8s LeaderWorketSet for multi-node deployment of LLama 3.1 405B model across P5 instances using NVIDIA Triton and NVIDIA TRT-LLM on EKS (Amazon Elastic Kubernetes Service) with support for autoscaling. This includes instructions for installing LeaderWorkerSet, building custom image to enable features like EFA, Helm chart and associated Python script. This deployment flow uses NVIDIA TensorRT-LLM as the inference engine and NVIDIA Triton Inference Server as the model server. See [multinode-triton-trtllm-inference](https://github.com/aws-samples/awsome-inference/tree/main/2.projects/multinode-triton-trtllm-inference) for more information.


### Files & Directories
1. `1.infrastructure/1_setup_cluster/trtllm_multinode_sample`: This directory contains the guide [Create_EKS_Cluster.md](/1.infrastructure/1_setup_cluster/multinode-triton-trtllm-inference/Create_EKS_Cluster.md) to setup 2x P5.48xlarge EKS cluster as well as example cluster config yaml file [`p5-trtllm-cluster-config.yaml`](/1.infrastructure/1_setup_cluster/multinode-triton-trtllm-inference/p5-trtllm-cluster-config.yaml) and EFS Persistent Volume Claim files in directory [pvc](/1.infrastructure/1_setup_cluster/multinode-triton-trtllm-inference/pvc)
2. The [Configure_EKS_Cluster.md](https://github.com/aws-samples/awsome-inference/blob/main/2.projects/multinode-triton-trtllm-inference/Configure_EKS_Cluster.md) guide to install necessary components like Prometheus Kubernetes Stack, EFA Plugin, LeaderWorkerSet, etc within the EKS cluster.
3. The [Deploy_Triton.md](https://github.com/aws-samples/awsome-inference/blob/main/2.projects/multinode-triton-trtllm-inference/Deploy_Triton.md) guide to build TRT-LLM engines for LLama 3.1 405B model, setup Triton model repository and install the multi-node deployment helm chart. This guide also covers testing the Horizontal Pod Autoscaler and Cluster Autoscaler and benchmarking LLM inference performance using genai-perf.

## TRITON TRT-LLM SAGEMAKER

These examples shows how to deploy LLMs like T5, Mistral using NVIDIA Triton TRT-LLM on Amazon SageMaker. See [triton-trtllm-sagemaker](2.projects/triton-trtllm-sagemaker) for more information.

## MIXTURE OF AGENTS (MoA)

Recent advances in large language models (LLMs) have shown substantial capabilities, but harnessing the collective expertise of multiple LLMs is an open direction. [Mixture-of-Agents (MoA)](https://github.com/togethercomputer/MoA) approach to leverages the collective strengths of multiple LLMs through a layered architecture. Each layer comprises multiple LLMs, and each model uses outputs from the previous layer's agents as auxiliary information. See [Mixture-of-Agents (MoA) on Amazon bedrock](/2.projects/mixture-of-agents) for more information.

### Files & Directories
1. [2.projects/mixture-of-agents/mixture-of-agents(MoA).ipynb](/2.projects/mixture-of-agents/mixture-of-agents(MoA).ipynb): Notebook that illustrates the MoA architecture and evaluation mechanism.
2. [2.projects/mixture-of-agents/outputs/](/2.projects/mixture-of-agents/outputs/): This directory consists of output of 2-layers MoA.
3. [2.projects/mixture-of-agents/alpaca_eval](/2.projects/mixture-of-agents/alpaca_eval/): This directory is from AlpacaEval GitHub repository and consists of results of Anthropic Claude 3.5 Sonnet. These results are used during evaluation.

## MIG
These days, the challenge with ML Inference workloads, is that not all workloads require the same amount of compute resources. With accelerated instances like the Amazon EC2 P5 (p5.48xlarge / p5e.48xlarge), or the Amazon EC2 P4 (p4d.24xlarge / p4de.24xlarge), customers would need to pay for the full instance of 8 GPUs. Additionally, some workloads may be too small to even run on a single GPU! To learn more about the specifics of GPU EC2 instances, check out this developer guide.

In 2020, NVIDIA released Multi-Instance GPU (MIG), alongside the Ampere Architecture that powers the NVIDIA A100 (EC2 P4) and NVIDIA A10G (EC2 G5) GPUs. With MIG, administrators can partition a single GPU into multiple smaller GPU units (called “MIG devices”). Each of these smaller GPU units are fully isolated, with their own high-bandwidth memory, cache, and compute cores.

### Files & Directories
1. [README.md](https://github.com/aws-samples/awsome-inference/blob/main/2.projects/mig-gpu-partitioning/README.md): Yes, this process is simple enough to only have a README! Note: This project only shows you how to set MIG up, and assumes you already have the cluster(s) set up, and your deployment ready to go.


