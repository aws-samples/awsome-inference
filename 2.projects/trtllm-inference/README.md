<!-- <p align="center">
  <a href="" rel="noopener">
 <img width=200px height=200px src="https://i.imgur.com/6wj0hh6.jpg" alt="Project logo"></a>
</p> -->

<h3 align="center">Inference on AWS P5 EC2 Instances with TensorRT-LLM</h3>
NOTE: THIS README IS STILL GETTING WORKED ON!!!

<!-- <div align="center">

[![Status](https://img.shields.io/badge/status-active-success.svg)]()
[![GitHub Issues](https://img.shields.io/github/issues/kylelobo/The-Documentation-Compendium.svg)](https://gitlab.aws.dev/smml/awsome-inference/-/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/kylelobo/The-Documentation-Compendium.svg)](https://gitlab.aws.dev/smml/awsome-inference/-/merge_requests)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](/LICENSE)

</div> -->

---

<p align="center"> This repository contains some example code to help you get started with performing inference on Large Language Models on AWS accelerated EC2 instances (with NVIDIA GPUs). 

You can optimize inference using [NVIDIA TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM?tab=readme-ov-file). 

As a quick introduction, you perform three (3) steps while using TensorRT-LLM <br>

1. Ensure you have your model definition and weights. 
    - For this example demonstration, we use [Meta Llama3-8B model](https://huggingface.co/meta-llama/Meta-Llama-3-8B) from Hugging Face.
    - Note: you'd need to provide your Hugging Face write token in order to clone this repository. Instructions on creating a write token can be found in [Hugging Face User Access Tokens](https://huggingface.co/docs/hub/en/security-tokens). 
    - If you have an accelerated instance of your own and would like to get started directly with TensorRT-LLM, check out [Turbocharging Meta Llama3 Performance with NVIDIA TensorRT-LLM and NVIDIA Triton Inference Server](https://developer.nvidia.com/blog/turbocharging-meta-llama-3-performance-with-nvidia-tensorrt-llm-and-nvidia-triton-inference-server/). Note: A lot of the NVIDIA TensorRT-LLM and NVIDIA Triton code was taken from here.
    - Further instructions on where to provide this write token can be found in the "Getting Started" section.

2. Convert the out-of-box model to a TensorRT optimized model
    - This can be done with the provided convert_checkpoint.py script.  
    - More information on an example on Llama can be found at [TensorRT-LLM/examples/llama](https://github.com/NVIDIA/TensorRT-LLM/tree/main/examples/llama).

3. Build an "efficient engine" with any optimizations you want. 
    - This can be done with the provided trtllm-build script.

4. Run inference on the engine you have built
    - This can be done with the provided run.py script

5. (Optional, but implemented in this example) Serve your LLM on the [Triton Inference Server](https://developer.nvidia.com/triton-inference-server)

- [NVIDIA's TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM?tab=readme-ov-file) <br>
- [Llama3-8B model on Hugging Face](https://huggingface.co/meta-llama/Meta-Llama-3-8B) <br>
- [Creating a Hugging Face Write Token](https://huggingface.co/docs/hub/en/security-tokens) <br>
- [Llama example on TesorRT-LLM Repo](https://github.com/NVIDIA/TensorRT-LLM/tree/main/examples/llama) <br>
- [Triton Inference Server](https://developer.nvidia.com/triton-inference-server) <br>

Scaling is done via Elastic Kubernetes Service (EKS). As you will see below, your AWS resources will be provisioned via the EKSCTL and the Kubectl.

</p>

## 📝 Table of Contents

- [About](#about)
- [Getting Started](#getting_started)
- [Deployment](#deployment)
- [Usage](#usage)
- [Built Using](#built_using)
- [TODO](../TODO.md)
- [Contributing](../CONTRIBUTING.md)
- [Authors](#authors)
- [Acknowledgments](#acknowledgement)

## 🧐 About <a name = "about"></a>

Performing Inference via TRTLLM on AWS P5 EC2 instances and scaling with Elastic Kubernetes Service (EKS)

Here's the architecture diagram without the frontend:
![Architecture Diagram Without Frontend](Images/AD-without-frontend.png)

And here's the architecture diagram with the frontend:
![Architecture Diagram With Frontend](Images/AD-with-frontend.png)

Note: The Management Instance is optional.

## 🏁 Getting Started <a name = "getting_started"></a>

These instructions will get you a copy of the project up and running on your AWS Account for development and testing purposes. See [deployment](#deployment) for notes on how to deploy the project on a live system.

### Prerequisites

What things you need to install the software and how to install them.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
```
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Mac OS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Windows
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```
2. Install [eksctl](https://eksctl.io/installation/)
3. Install [kubectl](https://kubernetes.io/docs/tasks/tools/)
4. Install [docker](https://docs.docker.com/get-docker/)
5. Have a VPC ready. The CloudFormation template to deploy the VPC can be found in

```
cd 0.\ Setup\ VPC
vpc-cf.yaml
```

Run 
```
aws cloudformation describe-stacks --stack-name trtllm-vpc-stack
```
and grab the IDs of the VPC, PublicSubnet1, PublicSubnet2, PrivateSubnet1 and PrivateSubnet2. Note: you can replace "trtllm-vpc-stack" with the stack name you provide.

Then, run
```
./edit-vpc-config.sh

# Example
Enter your VPC ID: vpc-xxxxxxxxxxxxxxxxx
Enter your Private Subnet 1 ID: subnet-xxxxxxxxxxxxxxxxx
Enter your Private Subnet 2 ID: subnet-xxxxxxxxxxxxxxxxx
Enter your Public Subnet 1 ID: subnet-xxxxxxxxxxxxxxxxx
Enter your Public Subnet 2 ID: subnet-xxxxxxxxxxxxxxxxx
```
and enter those 4 IDs. You are now ready to run the rest of the steps!

### Installing

A step by step series of examples that tell you how to get a development env running.

1. Run aws configure (us-east-2 in this example) to get your command line ready to interact with your AWS Account.
```
aws configure
```
2. Have a ecr repo name + tag in mind. <br>
This repository uses:
```
Repository Name: trtllm-inference-registry
Tag: latest
```
For more information on configuring an ECR (Elastic Container Registry) Repository, check [this](https://docs.aws.amazon.com/AmazonECR/latest/userguide/Repositories.html).

3. Run ./setup-secrets.sh and fill out whatever is prompted
```
cd ..
./setup-secrets

# Example:
Enter your Hugging Face Username: username
Enter your Hugging Face Access Token: hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Enter your Capacity Reservation ID: cr-0ce6be6d411d2f43f
Enter your Docker registry name (enter trtllm-inference-registry if you want to use default): trtllm-inference-registry
Enter the image tag for the image you'd like to use (enter latest if you want to use default): latest

# Example Response:
Updated the following files:
- 1.cluster-config.yaml with your Capacity Reservation ID
- 2. Setup Container/manifest.yaml with your AWS Account ID, Docker registry name, and image tag
- 2. Setup Container/ecr-secret.sh with your AWS Account ID
- 3.local_inference.sh with your Hugging Face Username and Access Token
```
4. (Optional) Add your optimization requirements to 3. Within Container/3.local_inference.sh
```
# Example Optimization:

# Step 1: Run the convert_checkpoint script to convert the model to TRT-LLM format.
# Build the Llama 8B model using a single GPU and FP16.
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tensorrt_llm/examples/llama/convert_checkpoint.py \
        --model_dir /tensorrt/models/${MODEL_NAME} \
        --output_dir /tensorrt/tensorrt-models/${MODEL_NAME}/0.10.0.dev2024043000/trt-checkpoints/fp16/1-gpu/ \
        --dtype float16

# Step 2: Create an engine based on the converted checkpoint above.
trtllm-build --checkpoint_dir /tensorrt/tensorrt-models/${MODEL_NAME}/0.10.0.dev2024043000/trt-checkpoints/fp16/1-gpu/ \
    --output_dir /tensorrt/tensorrt-models/${MODEL_NAME}/0.10.0.dev2024043000/trt-engines/fp16/1-gpu/ \
    --gpt_attention_plugin float16 \
    --gemm_plugin float16            
```
5. Run the following to get your AWS Account ID:
```
AWS_ACCOUNT_ID = $(aws sts get-caller-identity --query Account --output text)
```
6. Run docker build Dockerfile and push to your private ECR repo
```
cd 2.\ Setup\ Container
docker build Dockerfile
docker ps -a
```
Grab the image id of the Docker Image you just built.

7. Login to ECR and push your built image. Make sure you change the directory and tag names to your own directory and tag names:
```
aws ecr get-login-password --region us-east-2| docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.coM

docker tag image-id ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com/trtllm-inference-registry:latest

docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com/trtllm-inference-registry
```
8. Create your EKS Cluster and NodeGroup
```
cd ../1.\ Setup\ Cluster
eksctl create cluster cluster-config.yaml
```
Note: If you make changes to your nodegroup after this step, you can just run
```
eksctl create nodegroup
```
henceforth.

7. Set up your ECR Secret (Kubernetes Secret)
```
cd ../2.\ Setup\ Container
./ecr-secret.sh
```

8. Create your deployment: the pods that will be hosting your Engine used by the Triton Inference Server
```
kubectl apply -f manifest.yaml 

# Helpful kubectl commands
kubectl get pods
kubectl logs pod-name
```

9. Create an ingress of type Application Load Balancer to Load Balance to pods

Before running kubectl apply, you need to install the AWS Load Balancer Controller. You can follow the instructions found in ["Install the AWS Load Balancer Controller add-on using Kubernetes Manifests"](https://docs.aws.amazon.com/eks/latest/userguide/lbc-manifest.html) (recommended). Alternatively, if you like using HELM instead of manifests, you can follow the instructions ["Install the AWS Load Balancer Controller using Helm"](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html).

Once you've installed the load balancer controller, you can run:

```
kubectl apply -f ingress.yaml
```

At this point, you should be able to test whether your Triton Server is correctly set up on your pods, and is serving inference requests. You can run
```
kubectl get pods
kubectl logs pod-name
```
to check the logs of the pod and check if the Triton Server was stood up. Look for the following in the logs:
```
+------------------+---------+--------+
| Model            | Version | Status |
+------------------+---------+--------+
| ensemble         | 1       | READY  |
| postprocessing   | 1       | READY  |
| preprocessing    | 1       | READY  |
| tensorrt_llm     | 1       | READY  |
| tensorrt_llm_bls | 1       | READY  |
+------------------+---------+--------+
...
I0510 23:24:46.448586 800 grpc_server.cc:2463] Started GRPCInferenceService at 0.0.0.0:8001
I0510 23:24:46.448777 800 http_server.cc:4692] Started HTTPService at 0.0.0.0:8000
I0510 23:24:46.489784 800 http_server.cc:362] Started Metrics Service at 0.0.0.0:8002
```

Additionally, you can run 
```
curl -X POST k8s-default-trtllmin-<rest of ALB DNS>.us-east-2.elb.amazonaws.com/v2/models/ensemble/generate -d '{"text_input": "What is a Large Language Model?", "max_tokens": 200, "bad_words": "", "stop_words": ""}'
```
to test whether or not you are receiving the responses for your inference requests.

10. Set up auto scaling (CAS + HPA)

    CLUSTER AUTO SCALER 

    a. Deploy the Cluster Autoscaler to your cluster

    ```
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
    ```

    b. Add the required safe-to-evict annotation to the deployment

    ```
    kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false"
    ```

    c. Edit the Cluster Autoscaler Deployment as follows:
    ```
    kubectl -n kube-system edit deployment.apps/cluster-autoscaler

    # Change 1: Add your cluster name (or, replace trtllm-inference-cluster with your cluster name):
    - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/trtllm-inference-cluster

    # Change 2: Add the following two lines below the line above:
    - --balance-similar-node-groups
    - --skip-nodes-with-system-pods=false
    ```

    Here's what your file should look like after the changes:
    ```
        spec:
      containers:
      - command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/trtllm-inference-cluster
        - --balance-similar-node-groups
        - --skip-nodes-with-system-pods=false
    ```

    Note: If this step throws an error, run step d first, and then rerun step c.

    d. Set the Cluster Autoscaler Image version (it has to be the same as the Kubernetes version used by your cluster)
    ```
    kubectl -n kube-system set image deployment.apps/cluster-autoscaler cluster-autoscaler=us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler:v1.29.2
    ```

    You can run 
    ```
    kubectl -n kube-system get deployment cluster-autocaler -o yaml
    ```
    to verify that the image version got updated, along with the other changes you made above.

    You can also run 
    ```
    kubectl -n kube-system logs cluster-autoscaler
    ```
    to ensure that the cluster auto scaler is correctly monitoring.

    The cluster autoscaler is now deployed. Every time a pod is marked as 'unschedulable', it will go ahead and provision a new node, as long as another one is available. To test, you can also manually scale using:
    ```
    kubectl scale --replicas=x deploy llama3
    ```

    HORIZONTAL POD AUTOSCALER

    a. Install the Metrics Server
    ```
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    ```

    You can run
    ```
    kubectl -n kube-system get deployment metrics-server
    ```
    to verify that the metrics server was deployed. 

    c. Create the Horizontal Pod Autoscaler Resource
    ```
    # You can replace llama3 with your deployment name.
    kubectl autoscale deployment llama3 --cpu-percent=90 --min=1 --max=3
    ```

    You can run 
    ```
    kubectl get hpa
    kubectl describe hpa
    kubectl get pods
    ```
    to check the details of your Horizontal Pod Autoscaler.


11. Set up frontend (option of instance level or pod level)

To get this up and running ASAP, you can manually create an Application Load Balancer and Auto Scaling Group from your AWS Account. You can launch the instances into the existing public subnet (not recommended) or private subnet and create your routing rules accordingly. You can use the following user data script for your instances:
```
#!/bin/bash
apt-get update
apt-get install -y python-pip3
apt install -y python3-flask
apt install -y python3-requests
apt install -y python3-markdown2
apt install -y gunicorn
mkdir trtllm-inference-p5
cd trtllm-inference-p5
git init
git remote add -f origin https://amanshanbhag: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@github.com/amanshanbhag/trtllm-inference-p5.git
git config core.sparseCheckout true
echo "Frontend/" >> .git/info/sparse-checkout
git pull origin main
cd Frontend
gunicorn -c gunicorn_config.py app:app
```

Security Group Configuration:
- Allow inbound connections from the ALB Security Group
- Allow SSH access from developer IPs (all TCP)

For quick start, the ALB can allow inbound connections from anywhere. If this needs to be deployed as an internal tool, make sure you set up prefix lists for your ALB.

Make sure that the Load Balancer you create is public facing. You can now use the DNS of this frontend Application Load Balancer, and paste it into your web browser.

This is the frontend you should see.
![Screenshot of Frontend](Images/frontend-ss.png)

## ⛏️ Built Using <a name = "built_using"></a>

- [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) - Scaling using Kubernetes
- [AWS EC2 Accelerated Instances](https://aws.amazon.com/ec2/instance-types/)
- [NVIDIA TensorRT LLM](https://github.com/NVIDIA/TensorRT-LLM) - Inference Optimization on GPUs
- [NVIDIA Triton Inference Server](https://developer.nvidia.com/triton-inference-server) - Inference Serving
- [Flask](https://flask.palletsprojects.com/en/3.0.x/) - Frontend Server
- [Python http.server](https://docs.python.org/3/library/http.server.html) - Healthcheck Server for EKS ALB
- [Gunicorn](https://gunicorn.org/) - Frontend ALB Healthcheck Server

## ✍️ Authors <a name = "authors"></a>

- [@amanrsh](https://github.com/amanshanbhag) - Idea & Initial work

## 🎉 Acknowledgements <a name = "acknowledgement"></a>

- Hat tip to anyone whose code was used
- Inspiration
- References
