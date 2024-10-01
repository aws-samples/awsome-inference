# NVIDIA NIM on AWS Sagemaker

## What is NIM

[NVIDIA NIM](https://catalog.ngc.nvidia.com/orgs/nim/teams/mistralai/containers/mixtral-8x7b-instruct-v01) enables efficient deployment of large language models (LLMs) across various environments, including cloud, data centers, and workstations. It simplifies self-hosting LLMs by providing scalable, high-performance microservices optimized for NVIDIA GPUs. NIM's containerized approach allows for easy integration into existing workflows, with support for advanced language models and enterprise-grade security. Leveraging GPU acceleration, NIM offers fast inference capabilities and flexible deployment options, empowering developers to build powerful AI applications such as chatbots, content generators, and translation services.

### Features

NIM abstracts away model inference internals such as execution engine and runtime operations. They are also the most performant option available whether it be with [TRT-LLM](https://github.com/NVIDIA/TensorRT-LLM), [vLLM](https://github.com/vllm-project/vllm), and others. NIM offers the following high performance features:

1. Scalable Deployment that is performant and can easily and seamlessly scale from a few users to millions.
2. Advanced Language Model support with pre-generated optimized engines for a diverse range of cutting edge LLM architectures.
3. Flexible Integration to easily incorporate the microservice into existing workflows and applications. Developers are provided with an OpenAI API compatible programming model and custom NVIDIA extensions for additional functionality.
4. Enterprise-Grade Security emphasizes security by using safetensors, constantly monitoring and patching CVEs in our stack and conducting internal penetration tests.

Here is a link to the [NIM Support Matrix](https://docs.nvidia.com/nim/large-language-models/latest/support-matrix.html)

### Architecture

NIMs are packaged as container images on a per model/model family basis. Each NIM is its own Docker container with models, such as Mistral and Llama. These containers include a runtime that runs on any NVIDIA GPU with sufficient GPU memory, but some model/GPU combinations are optimized. In this sample, we will be using the [NVIDIA NIM public ECR gallery on AWS](https://gallery.ecr.aws/nvidia/nim).

In these examples we show how to deploy `Mixtral 8x7B` and `Llama3 70B` on a `p4d.24xlarge` instance with NIM on Amazon SageMaker.

### In this directory...
You will find "plug-and-play" notebook samples for running your NIM on [SageMaker Notebooks](https://aws.amazon.com/sagemaker/notebooks/). 

