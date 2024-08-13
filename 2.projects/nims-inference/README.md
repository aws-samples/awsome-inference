<!-- <p align="center">
  <a href="" rel="noopener">
 <img width=200px height=200px src="https://i.imgur.com/6wj0hh6.jpg" alt="Project logo"></a>
</p> -->

<h3 align="center">Inference on AWS EC2 Instances with NVIDIA NIMs</h3>
NOTE: THIS README IS STILL GETTING WORKED ON!!!

---

<p align="center"> This repository contains some example code to help you get started with performing inference on Large Language Models on AWS accelerated EC2 instances (with NVIDIA GPUs). 

[NVIDIA NIM](https://developer.nvidia.com/nim) is a set of accelerated inference microservices that allow developers to run models on NVIDIA GPUs. With NIM, developers can get inference workloads set up quickly and efficiently. For more information on NIMs, check out the [Github repo](https://github.com/NVIDIA/nim-deploy/tree/main) (from NVIDIA).

This repo contains an example to be able to run NIMs on AWS and scale using [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).
</p>

## Prerequisite
#### Setup the EKS cluster
Please make sure the EKS cluster has been setup, either from a given example in [infrastructure](infrastructure)

#### Set up your NGC API Key
Please make sure you have the [NGC API key](https://docs.nvidia.com/ngc/gpu-cloud/ngc-user-guide/index.html#ngc-api-keys) ready to download the NIM docker images.


## Deploy NIM
In this example, we are using the helm example in the `nim-deploy` provided by NVIDIA. More on this directory can be found in NVIDIA's Github Repo [nim-deploy](https://github.com/NVIDIA/nim-deploy/tree/main). 

Here, we show an example of deploying NIM llama3-8b-instruct model, with code to benchmark it using `genai-perf`. 

`genai-perf` is a command-line benchmarking tool, provided by NVIDIA, for measuring inference metrics of genAI models as served through an inference server. Some of the metrics provided are `output token throughput`, `time to first token` `inter token latency`, and `request throughput`. For more information on `genai-perf`, check out the [GenAI-Perf Documentation](https://docs.nvidia.com/deeplearning/triton-inference-server/user-guide/docs/client/src/c%2B%2B/perf_analyzer/genai-perf/README.html).

Please check the Trobleshooting section if you encounter any issues.

### 1. Deploy
```bash
export NGC_CLI_API_KEY="key from ngc"
cd nim-deploy/helm
helm install my-nim nim-llm/ --set model.ngcAPIKey=$NGC_CLI_API_KEY --set persistence.enabled=true
```

Note: you also have the option to use custom values helm files.

### 🔧 (Optional) 2. Test
Note: To run this test step, you would need to set up the `nim` namespace. The example provided here runs everything in the default namespace. Follow the instructions in the `nim-deploy/helm` README to deploy the nim namespace. Running the `helm test` command below is optional.

First, you need to make sure that your NIM pod is up and running:
```bash
kubectl get pods
```
Make sure that the NIM pod has status RUNNING.

Once that is true, you can run:
```bash
helm test my-nim --logs
```
Which will run some simple inference requests. If the three tests pass, you'll know the deployment was successful.

### 3. Query
To try out the NIM query, please port-forward the service
```bash
kubectl port-forward service/my-nim-nim-llm 8000:8000
```

And to an example `curl` (from NVIDIA):
```bash
curl -X 'POST' \
'http://localhost:8000/v1/chat/completions' \
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

### 🎈 4. Application
 Now that you've tested your NIM, you can set up a service of type ClusterIP to expose a port on your container. This way, you can set up other services like frontends or benchmarking tools to be able to send inference requests on your behalf.
```bash
kubectl apply -f nim-deploy/helm/nim-llm/nodeport.yaml
```

### 🚀 5. (TODO) Scaling
This section is coming soon...

## Benchmark
In this example, the `genai-perf` tool is used for the benchmark. For more information, check out the [GenAI-Perf Doc](https://docs.nvidia.com/deeplearning/triton-inference-server/user-guide/docs/client/src/c%2B%2B/perf_analyzer/genai-perf/README.html)

The below example `benchmark_concurrency.sh` will run multiple concurrencies benchmark using `genai-perf`.

```bash
kubectl apply -f nim-deploy/helm/nim-llm/nodeport.yaml

cd benchmark

# Example of using genai-perf benchmark
./benchmark_concurrency.sh

# Copy benchmark data from pod to local
kubectl cp <POD_NAME>:/workspace/benchmarks <YOUR_LOCAL_PATH

# Terminate the genai-perf
./terminate_benchmark.sh
```

The `genai-perf` offers a bunch of flags that you can configure as required to collect metrics. You can check out all the flags here. You will also notice a `sleep 36000000000000` statement in the `args` section. This is here so that you can either `kubectl exec` into the pod, or so that you can grab the json and csv files generated by genai-perf.


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
- [@joeychou](https://github.com/JoeyTPChou) 

## 🎉 Acknowledgements <a name = "acknowledgement"></a>

- Hat tip to anyone whose code was used
- Inspiration
- References
