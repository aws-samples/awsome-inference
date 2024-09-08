<!-- <p align="center">
  <a href="" rel="noopener">
 <img width=200px height=200px src="https://i.imgur.com/6wj0hh6.jpg" alt="Project logo"></a>
</p> -->

<h3 align="center">Scaling your NIM workloads on EKS</h3>
NOTE: THIS README IS STILL GETTING WORKED ON!!!

---

<p align="center"> This repository contains some example code to help you get started with performing inference on Large Language Models on AWS accelerated EC2 instances (with NVIDIA GPUs). 

[NVIDIA NIM](https://developer.nvidia.com/nim) is a set of accelerated inference microservices that allow developers to run models on NVIDIA GPUs. With NIM, developers can get inference workloads set up quickly and efficiently. For more information on NIMs, check out the [Github repo](https://github.com/NVIDIA/nim-deploy/tree/main) (from NVIDIA).

This repo contains an example to be able to run NIMs on AWS and scale using [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).

**If you want to get set up with NIMs quickly on AWS, please check out [nims-inference](https://github.com/aws-samples/awsome-inference/tree/main/2.projects/nims-inference/). If you'd like to deploy your NIM on EKS with Autoscaling, Load Balancing, and custom metric collection with Prometheus (`num_requests_running`), continue following this guide.**
</p>

## Prerequisite
#### Setup the EKS cluster
Please make sure the EKS cluster has been setup, from a given example in [infrastructure](infrastructure)

#### Set up your NGC API Key
Please make sure you have the [NGC API key](https://docs.nvidia.com/ngc/gpu-cloud/ngc-user-guide/index.html#ngc-api-keys) ready to download the NIM docker images.

## Deploy NIM
If you followed the example in [nims-inference](https://github.com/aws-samples/awsome-inference/tree/main/2.projects/nims-inference/), which uses NVIDIA's GitHub Repository [nim-deploy](https://github.com/NVIDIA/nim-deploy/tree/main), you would have used pre-set values in your Helm files.

In this example, we will walk you through using a custom values Helm file. Along with that, we will also demonstrate how to scale using custom metrics scrpaed by Prometheus, and how to load balance on EKS.

For benchmarking, please check out [benchmark](https://github.com/aws-samples/awsome-inference/tree/main/2.projects/nims-inference/benchmark) that uses the `genai-perf` tool.

Please check the Trobleshooting section if you encounter any issues.

### 1. Deploy

To deploy your custom-value NIM, we need to first set up Kubernetes Secrets. There are two types of secrets that we'll need to create: a generic secret, and a Docker Registry secret to let you pull images from NGC.

```bash
export NGC_CLI_API_KEY="key from ngc"
kubectl create secret generic ngc-api --from-literal=NGC_CLI_API_KEY=$NGC_CLI_API_KEY
kubectl create secret docker-registry registry-secret --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=$NGC_CLI_API_KEY
```

Once you have that set up, we can deploy our NIM with a custom value file. We'll be using the manifest file `custom-values-ebs-sc.yaml` in `storage/`. Before we do that, we need to create the EBS storage class (EFS example coming soon).

```bash
bash setup/setup.sh
```

You can now use Helm to deploy the custom values manifest
```bash
helm install nim-llm ../../../helm/nim-llm -f storage/custom-values-ebs-sc.yaml
```

### 🔧 2. Monitoring
We will be using [Prometheus](https://prometheus.io/) to scrape the `num_requests_running` metric from the NIM pods.

Install the Prometheus stack using helm
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack
```

Install the Prometheus adapter. This adapter is what will be used to collect custom metrics (pushed onto the Prometheus instance by the NIM pods). We'll be using the `monitoring/custom-rules.yaml` manifest to tell the Prometheus Adapter what metric to look for.
```bash
helm install prometheus-adapter prometheus-community/prometheus-adapter -f monitoring/custom-rules.yaml
```

With this, you have monitoring set up! If you'd like to confirm whether the `num_requests_running` metric is being scraped by Prometheus and emitted by your NIM pods, you can access the Prometheus UI. To do so, run
```bash
kubectl port-forward svc/prometheus-operated 9090
```
This command will forward the Prometheus service port (9090) to your local machine on port 9090. You can then access the Prometheus UI by opening up http://localhost:9090 on your web browser.

On the Web UI, check the Targets: In the Prometheus UI, navigate to the "Status" -> "Targets" page. This page shows a list of all registered targets (endpoints) that Prometheus is scraping metrics from. Make sure that your NIM pods are on here.

Once you confirm that your pods are being scraped, query the metric: On the UI, check out the "Graph" tab and enter the following query:
```
num_requests_running
```
This will show you the time series data for the `num_requests_running` metric across all the NIM pods that you have deployed. 

Note: Make sure you send some requests to your pod **before** trying to query for the metric, since otherwise it won't show you the metric.

### 🚀 3. Scaling
In this section, we will provide you with different options to configure scaling your NIM workloads on Amazon EKS. Both of these are valid configurations, and have their own use-cases. 

#### Option 1: HPA + CAS
We'll be using the Kubernetes Horizontal Pod Autoscaler (HPA) to scale our NIM workload. 

To use the HPA, we would need to install the Metrics Server. To do this, run:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

To verify that the metrics server was deployed, run
```bash
kubectl -n kube-system get deployment metrics-server
```

Lastly, we can create the HPA resource using the `hpa-num-requests.yaml` manifest in `scaling/`. This HPA scales based on the custom metric `num_requests_running` scraped by Prometheus. You can change the following lines to set the thresholds for scaling:
```yaml
      target:
        # 10000 milli-requests per second = 10 requests 
        type: AverageValue
        averageValue: 100000m
```

To create the HPA resource, run
```bash
kubectl apply -f scaling/hpa-num-requests.yaml
```

If you'd like to also deploy a Cluster Autoscaler (CAS), please check out the [CAS scaling section](https://github.com/aws-samples/awsome-inference/tree/main/2.projects/trtllm-inference#cluster-auto-scaler) in the TensorRT-LLM example.

#### Option 2: KEDA + Karpenter
To get started with KEDA, you’d need to deploy KEDA onto your EKS Cluster. You can follow the following steps to do so [using HELM](https://keda.sh/docs/2.15/deploy/#helm).

To configure auto scaling at the pod level (similar to HPA), we use KEDA to define a custom resource called ScaledObject, as shown in the file provided in scaling/kedas-config.yaml:

The manifest defines a resource ScaledObject named keda-prometheus-hpa. This ScaledObject is responsible for scaling our NIM pod deployments and has a minReplicaCount of 1, meaning 1 pod is always running. As required, it scales the pods based on the custom metric num_requests_running, as emitted by the NIM pods and scraped by Prometheus. 

We use the query max(num_requests_running) by (pod) so that if any single pod has more than 100 incoming requests, we scale up. KEDA also scales down the replicas after the num_requests_running has been below 100 for more than 5 minutes.

To set up node scaling (similar to CAS), you can use Karpenter. You can use the [Karpenter Documentation](https://karpenter.sh/docs/getting-started/migrating-from-cas/) to run the steps required to set up Karpenter on your EKS Cluster.

Once you have Karpenter set up on your EKS Cluster, you can create a manifest to create a resource of type NodePool (i.e., a Karpenter configuration). You can find the Karpenter configuration we use in scaling/karpenter-config.yaml 

In this Karpenter NodePool definition, Karpenter can launch instances from on-demand capacity pools. This is done since this blog assumes that you’re using either On Demand (OD), On Demand Capacity Reservation (ODCR), or Capacity Blocks (CB) for your NIM deployment. If you’d like to use Spot instances, feel free to add “spot” to that array.

Instances launched must be from the g (GPU accelerated) class, with instance generation being greater than 4. So, in this case, g5 and g6 are acceptable, but g4 is not. Feel free to change these values depending on your specific cluster configuration.

The default NodePool definition also defines disruption policies, which means that any underutilized nodes will be removed (scaled down) so that pods can be consolidated to run on fewer or smaller nodes. The expireAfter parameter specified the maximum lifetime of any node before scaling down. 

We also provision an EC2NodeClass with blockDeviceMappings, so Karpenter can provision instances with large enough EBS volumes. This template uses 500GB EBS gp3 volumes, but feel free to change this as required.

### 4. Load Balancing 
To load balance across pods, we will be creating a Kubernetes ingress of type Application Load Balancer.

You would first need to install the AWS Load Balancer Controller. You can follow the instructions found in ["Install the AWS Load Balancer Controller add-on using Kubernetes Manifests"](https://docs.aws.amazon.com/eks/latest/userguide/lbc-manifest.html) (recommended). Alternatively, if you like using HELM instead of manifests, you can follow the instructions ["Install the AWS Load Balancer Controller using Helm"](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html).

Once you've installed the load balancer controller, you can run
```bash
kubectl apply -f ingress/ingress.yaml
```

**Note: Once you deploy your Application Load Balancer, please make sure that the security group associated with the ALB is part of the ingress rules of your instances, otherwise your ALB will not be able to serve traffic to your instances, and by extension, your pods.**

### 🎈 5. Testing
To test whether your ALB is able to serve traffic to your pods, you can run 
```bash
curl -X 'POST' \
'http://<ALB-DNS>/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "messages": [
    {
      "content": "You are a polite and respectful chatbot helping people plan a vacation.",
      "role": "system"
    },
    {
      "content": "What should I do for a 4 day vacation in Spain?",
      "role": "user"
    }
  ],
  "model": "meta/llama3-8b-instruct",
  "max_tokens": 16,
  "top_p": 1,
  "n": 1,
  "stream": false,
  "stop": "\n",
  "frequency_penalty": 0.0
}'
```

### 6. Observability
To set up Observability, we will install [Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/installation/kubernetes/). For this example, we are primarily using the Grafana defaults, but we are overriding several parameters. We are setting the storage class to gp2, setting up the admin password, configuring the datasource to point to Prometheus and creating an external load balancer for the service.

First, take a look at `grafana.yaml` under grafana/. This file sets up prometheus as a data source for Grafana, so any custom metrics scraped by Prometheus (i.e., `num_requests_running` should be visible on Grafana).

You can run 
```bash
kubectl create namespace grafana

helm install grafana grafana/grafana \
    --namespace grafana \
    --set persistence.storageClassName="gp2" \
    --set persistence.enabled=true \
    --set adminPassword='EKS!sAWSome' \
    --values ${HOME}/environment/grafana/grafana.yaml \
    --set service.type=LoadBalancer
```

Once deployed, you can check status by running
```bash
kubectl get all -n grafana

# Example output
NAME                          READY   STATUS    RESTARTS   AGE
pod/grafana-f64dbbcf4-794rk   1/1     Running   0          55s
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP                                                               PORT(S)        AGE
service/grafana   LoadBalancer   10.100.60.167   aa0fa7322d86e408786cdd21ebcc461c-1708627185.us-east-2.elb.amazonaws.com   80:31929/TCP   55s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/grafana   1/1     1            1           55s

NAME                                DESIRED   CURRENT   READY   AGE
replicaset.apps/grafana-f64dbbcf4   1         1         1       55s
```

You can get the ALB URL using
```bash
export GRAFANA_ALB=$(kubectl get svc -n grafana grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$GRAFANA_ALB"
```

When logging in, please use username `admin` and the password you specified in the `helm install` command above. You can retrieve this password using
```bash
kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

## Benchmark
To learn more about benchmarking please check out [benchmark](https://github.com/aws-samples/awsome-inference/tree/main/2.projects/nims-inference/benchmark).

## Troubleshooting
If you run into an error with Kubernetes PVCs, follow these steps.

1. Check all pods with `kubectl get pods -A`
2. Get logs of the `aws-node-xxxx` pod and check the three containers (`-c`):
    * `aws-node`
    * `aws-eks-nodeagent`
    * `aws-vpc-cni-init`
3. Check the status of your Persistent Volume Claims (PVCs) with `kubectl get pvc -A`. If the controller is not installed, or you see an error here, run the steps below.
4. To install controller, run:
```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.27"
```
5. Once this is run, you should have the ebs csi controller installed on your cluster!

This should resolve any issues you may have with setting up PVCs on your cluster. Redeploy your helm chart after making this change!

## ⛏️ Built Using <a name = "built_using"></a>

- [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) - Scaling using Kubernetes
- [AWS EC2 Accelerated Instances](https://aws.amazon.com/ec2/instance-types/)
ADD NIMs LINKS
- [NVIDIA NIMs](https://github.com/NVIDIA/nim-deploy/tree/main) - Getting Inference on models set up quickly 

## ✍️ Authors <a name = "authors"></a>

- [@amanrsh](https://github.com/amanshanbhag)
