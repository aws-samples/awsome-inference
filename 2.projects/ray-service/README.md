<!-- <p align="center">
  <a href="" rel="noopener">
 <img width=200px height=200px src="https://i.imgur.com/6wj0hh6.jpg" alt="Project logo"></a>
</p> -->

<h3 align="center">Inference on AWS EKS with RayService</h3>
NOTE: THIS README IS STILL GETTING WORKED ON!!!

---

<p align="center"> This repository contains some example code to help you get started with performing inference on AI/ML models on AWS accelerated EC2 instances with the help of Ray (with NVIDIA GPUs). 

[Ray](https://docs.ray.io/en/master/index.html) is an open source framework to build and scale your ML and Python applications easily. 

[RayService](https://docs.ray.io/en/latest/serve/index.html) is a scalable model serving library for building online inference APIs. Ray Serve is a flexible toolkit for deploying various models, including deep learning, Scikit-Learn, and custom Python logic.Built on Ray, it scales across multiple machines and offers flexible resource allocation, enabling efficient, cost-effective model deployment.

This repo contains an example to be able to run [StableDiffusion](https://huggingface.co/stabilityai/stable-diffusion-2), [MobileNet](https://arxiv.org/abs/1801.04381), and [DETR](https://huggingface.co/docs/transformers/en/model_doc/detr) models on AWS and scale using [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).
</p>

## Prerequisite
#### Setup the EKS cluster
Please make sure the EKS cluster has been setup. Example EKS cluster set up in [infrastructure](infrastructure).

#### Set up your AWS Kubectl Secret (Optional)
Please run [`./kubectl-secret-keys.sh`](kubectl-secret-keys.sh). This will create a kubectl secret if python code needs to access your AWS credentials (like referencing a private S3 bucket). 


## Deploy KubeRay Operator
Please run [`./deploy-kuberay-operator.sh`](deploy-kuberay-operator.sh) to create a kuberay-operator pod in your EKS cluster within your head node. Upon successful deployment, it will be in Running state. To check the state of the pod in teh cluster, use command [`kubectl get pods`]. 

The KubeRay Operator allows for the deployment of the RayService. Now you are ready to get serving. 

Note: In both of these examples, you have the option to edit the RayService yaml file ([ray-service.mobilenet.yaml](/2.projects/ray-service/MobileNet/ray-service.mobilenet.yaml) , [ray-service.stable-diffusion.yaml](/2.projects/ray-service/StableDiffusion/ray-service.stable-diffusion.yaml)). This can include adjusting the number of worker pods, adjusting the resource requirements of your pods, mounting any volumes, adding tolerations to your worker pods, etc. And overall, these yaml files can be used as a template for inference on other models as well. 

## [MobileNet on EKS using Ray](https://docs.ray.io/en/latest/cluster/kubernetes/examples/mobilenet-rayservice.html)

### 1. Deploy RayService cluster. 
```bash
cd MobileNet
kubectl apply -f ray-service.mobilenet.yaml
```
Run this command to deploy your RayService cluster.

### 🔧 2. Test

First, you need to make sure that your Ray pods are up and running. You should see one head pod and one worker pod:
```bash
kubectl get pods
```
Make sure that both pods have status RUNNING.

### 2.5. Ray Dashboard (Optional)
If you would like to access the Ray Dashboard to see a UI for your cluster, please follow.

```bash
kubectl get svc
```

Locate the head pod service that will look something like "rayservice-mobilenet-raycluster-XXXXX-head-svc". Replace this with the service in the next command. 

Now run,
```bash
kubectl port-forward svc/stable-diffusion-raycluster-XXXXX-head-svc 8265:8265
```


### 3. Forward the port for Ray Serve
To try out the MobileNet query, please port-forward the service
```bash
kubectl port-forward svc/rayservice-mobilenet-serve-svc 8000
```

Note: The Serve service is created after the Ray Serve applications are ready and running so this process may take approximately 1 minute after the pods are running. 

### 🎈 4. Send Request to Image Classifier
Prepare one of your own image files. Update `image_path` variable in ['mobilenet_req.py`](MobileNet/mobilenet_req.py) with the location of your .png file. Then you can send your request. 

```bash
python mobilenet_req.py
# sample output: {"prediction":["n04285008","sports_car",0.7204936146736145]}
```



## [Stable Diffusion on EKS using Ray](https://docs.ray.io/en/latest/cluster/kubernetes/examples/stable-diffusion-rayservice.html)


Note: This repository contains the actual get and fulfill request code. You have the option to put this code (or your own code) into your own S3 bucket and reference the zipped code from there. In order to use S3, you need to run ['kubectl-secret-keys.sh'](/2.projects/ray-service/kubectl-secret-keys.sh) to make secrets of your AWS credentials. Then you need to uncomment the secret references in the env variables in the Ray cluster. 


### 1. Deploy RayService cluster. 
```bash
cd StableDiffusion
kubectl apply -f ray-service.stable-diffusion.yaml
```
Run this command to deploy your RayService cluster.

### 🔧 2. Test

First, you need to make sure that your Ray pods are up and running. You should see one head pod and one worker pod:
```bash
kubectl get pods
```
Make sure that both pods have status RUNNING.

### 2.5. Ray Dashboard (Optional)
If you would like to access the Ray Dashboard to see a UI for your cluster, please follow.

```bash
kubectl get svc
```

Locate the head pod service that will look something like "rayservice-mobilenet-raycluster-XXXXX-head-svc". Replace this with the service in the next command. 

Now run,
```bash
kubectl port-forward svc/stable-diffusion-raycluster-XXXXX-head-svc 8265:8265
```


### 3. Forward the port for Ray Serve
To try out the MobileNet query, please port-forward the service
```bash
kubectl port-forward svc/stable-diffusion-serve-svc 8000
```

Note: The Serve service is created after the Ray Serve applications are ready and running so this process may take approximately 1 minute after the pods are running. 

### 🎈 4. Send Request to Image Classifier
Prepare one of your own image files or you can use one of the examples in the folder. Update `image_path` variable in ['stable_diffusion_req.py`](StableDiffusion/stable_diffusion_req.py). Then you can send your request. This will upload output.png result in your current folder. 

```bash
python stable_diffusion_req.py
```


## [DETR on EKS using Ray](https://huggingface.co/facebook/detr-resnet-50)



### 1. Deploy RayService cluster. 
```bash
cd StableDiffusion
kubectl apply -f ray-service.detr.yaml
```
Run this command to deploy your RayService cluster.

### 🔧 2. Test

First, you need to make sure that your Ray pods are up and running. You should see one head pod and one worker pod:
```bash
kubectl get pods
```
Make sure that both pods have status RUNNING.

### 2.5. Ray Dashboard (Optional)
If you would like to access the Ray Dashboard to see a UI for your cluster, please follow.

```bash
kubectl get svc
```

Locate the head pod service that will look something like "detr-raycluster-XXXXX-head". Replace this with the service in the next command. 

Now run,
```bash
kubectl port-forward svc/detr-raycluster-XXXXX-head 8265:8265
```


### 3. Forward the port for Ray Serve
To try out the MobileNet query, please port-forward the service
```bash
kubectl port-forward svc/detr-serve-svc 8000
```

Note: The Serve service is created after the Ray Serve applications are ready and running so this process may take approximately 1 minute after the pods are running. 

### 🎈 4. Send Request to Image Classifier
Prepare one of your own image files or you can use one of the examples in the folder. Update `image_path` variable in ['detr_req.py`](DETR/detr_req.py). Then you can send your request. This will classify your objects and provide coordinate locations of where the object is in your image. 

```bash
python stable_diffusion_req.py
```




## Troubleshooting


## ⛏️ Built Using <a name = "built_using"></a>

- [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) - Scaling using Kubernetes
- [AWS EC2 Accelerated Instances](https://aws.amazon.com/ec2/instance-types/)
- [Ray](https://www.ray.io/)
- [Ray Serve](https://docs.ray.io/en/latest/serve/index.html)
- [MobileNet](https://docs.ray.io/en/latest/cluster/kubernetes/examples/mobilenet-rayservice.html)
- [StableDiffusion Instructions](https://docs.ray.io/en/latest/cluster/kubernetes/examples/stable-diffusion-rayservice.html)
- [StableDiffusion Code](https://docs.ray.io/en/latest/serve/tutorials/stable-diffusion.html)
- [aws-do-ray](TBD)




## ✍️ Authors <a name = "authors"></a>

- [@mvincig](https://github.com/mvinci12)
- [@flostahl](https://github.com/flostahl-aws)



