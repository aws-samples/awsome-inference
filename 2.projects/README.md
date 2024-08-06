## Projects

Once you have your infrastructure set up, your next step is to choose your inference solution. This sub-directory consists of example end-to-end implementations of different inference optimization frameworks on AWS.

The major components of this directory are:
```bash
|-- nims-inference/                      
|-- trtllm-inference/ 
|-- ray-service/                
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
1. `nim-deploy/`: This directory, provided by NVIDIA, contains helm charts and templates to get inference with NIMs set up quickly and efficiently.
2. `benchmark/`: This directory consists of example benchmarking scripts that you can use as-is, or with additional flags as defined by NVIDIA's `genai-perf` tool.


## RAY-SERVICE

[RayService](https://docs.ray.io/en/latest/serve/index.html) is a scalable model serving library for building online inference APIs. Ray Serve is a flexible toolkit for deploying various models, including deep learning, Scikit-Learn, and custom Python logic. Built on Ray, it scales across multiple machines and offers flexible resource allocation, enabling efficient, cost-effective model deployment. This repo contains an example to be able to run [StableDiffusion](https://huggingface.co/stabilityai/stable-diffusion-2), [MobileNet](https://arxiv.org/abs/1801.04381), and [DETR](https://huggingface.co/docs/transformers/en/model_doc/detr) models on AWS and scale using [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).
</p>

### Files & Directories
1. `MobileNet/`: This directory contains a Ray Service yaml and python code to run inference for this image classification model.
2. `StableDiffusion/`: This directory contains a Ray Service yaml and python code to run inference for this text-to-image model. 
3. `DETR/`: This directory contains a Ray Service yaml and python code to run inference for this object detection model.