# Steps to deploy multi-node LLM using Triton + TRT-LLM on EKS cluster

## 1. Build the custom container image and push it to Amazon ECR

We need to build a custom image on top of Triton TRT-LLM NGC container to include the kubessh file, server.py, and other EFA libraries and will then push this image to Amazon ECR. You can take a look at the [Dockerfile here](/2.projects/multinode-triton-trtllm-inference/multinode_helm_chart/containers/triton_trt_llm.containerfile).

```
## AWS
export AWS_REGION=us-east-1
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

## Docker Image
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
export IMAGE=triton_trtllm_multinode
export TAG=":24.08"

docker build \
  --file ./multinode_helm_chart/containers/triton_trt_llm.containerfile \
  --rm \
  --tag ${REGISTRY}${IMAGE}${TAG} \
  .

echo "Logging in to $REGISTRY ..."
aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY

# Create registry if it does not exist
REGISTRY_COUNT=$(aws ecr describe-repositories | grep ${IMAGE} | wc -l)
if [ "$REGISTRY_COUNT" == "0" ]; then
        echo ""
        echo "Creating repository ${IMAGE} ..."
        aws ecr create-repository --repository-name ${IMAGE}
fi

# Push image
docker image push ${REGISTRY}${IMAGE}${TAG}
```

## 2. Setup Triton model repository for LLM deployment:

To build the TRT-LLM engine and set up Triton model repository inside the compute node use the following steps:

### a. Modify the `setup_ssh_efs.yaml` file

We use the [`setup_ssh_efs.yaml`](/2.projects/multinode-triton-trtllm-inference/multinode_helm_chart/setup_ssh_efs.yaml) file which does "sleep infinity" to set up ssh access inside the compute node along with EFS.

Adjust the following values:

- `image` : change image tag. Default is 24.08 which supports TRT-LLM v0.12.0
- `nvidia.com/gpu` : set to the number of GPUs per node in your cluster, adjust in both the limits and requests section
- `claimName` : set to your EFS pvc name

### b. SSH into compute node and build TRT-LLM engine

Deploy the pod:

```
kubectl apply -f multinode_helm_chart/setup_ssh_efs.yaml
kubectl exec -it setup-ssh-efs -- bash
```

Clone the Triton TRT-LLM backend repository:

```
cd <EFS_mount_path>
git clone https://github.com/triton-inference-server/tensorrtllm_backend.git -b v0.12.0
cd tensorrtllm_backend
git lfs install
git submodule update --init --recursive
```

Build a Llama3.1-405B engine with Tensor Parallelism=8, Pipeline Parallelism=2 to run on 2 nodes of p5.48xlarge (8xH100 GPUs each), so total of 16 GPUs across 2 nodes. **Make sure to upgrade Huggingface `transformers` version to latest version otherwise convert_checkpoint.py can fail.** For more details on building TRT-LLM engine please see [TRT-LLM LLama 405B example](https://github.com/NVIDIA/TensorRT-LLM/tree/main/examples/llama#run-llama-31-405b-model), and for other models see [TRT-LLM examples](https://github.com/NVIDIA/TensorRT-LLM/tree/main/examples).

```
cd tensorrt_llm/examples/llama

pip install -U "huggingface_hub[cli]"
huggingface-cli login
huggingface-cli download meta-llama/Meta-Llama-3.1-405B --local-dir ./Meta-Llama-3.1-405B --local-dir-use-symlinks False

python3 convert_checkpoint.py --model_dir ./Meta-Llama-3.1-405B \
                             --output_dir ./converted_checkpoint \
                             --dtype bfloat16 \
                             --tp_size 8 \
                             --pp_size 2 \
                             --load_by_shard \
                             --workers 2

trtllm-build --checkpoint_dir ./converted_checkpoint \
             --output_dir ./output_engines \
             --max_num_tokens 4096 \
             --max_input_len 65536 \
             --max_seq_len 131072 \
             --max_batch_size 8 \
             --use_paged_context_fmha enable \
             --workers 8
```

### c. Prepare the Triton model repository

We will set up the model repository for TRT-LLM ensemble model. For more details on setting up model config files please see [model configuration](https://github.com/triton-inference-server/tensorrtllm_backend/blob/main/docs/model_config.md) and [here](https://github.com/triton-inference-server/tensorrtllm_backend).
```
# Example Tokenizer Path
export PATH_TO_TOKENIZER=/var/run/models/tensorrtllm_backend/tensorrt_llm/examples/llama/Meta-Llama-3.1-405B

# Example Engine Path
export PATH_TO_ENGINE=/var/run/models/tensorrtllm_backend/tensorrt_llm/examples/llama/trt_engines/tp8-pp2

cd <EFS_MOUNT_PATH>/tensorrtllm_backend
mkdir triton_model_repo

rsync -av --exclude='tensorrt_llm_bls' ./all_models/inflight_batcher_llm/ triton_model_repo/

# Replace PATH_TO_AWSOME_INFERENCE_GITHUB with path to where you cloned the GitHub repo
bash PATH_TO_AWSOME_INFERENCE_GITHUB/2.projects/multinode-triton-trtllm-inference/update_triton_configs.sh
```

> [!Note]
> If you choose to not use environment variables for your paths, be sure to substitute the correct values for `<PATH_TO_TOKENIZER>` and `<PATH_TO_ENGINES>` in the example above. Instead of using the shell script, please copy paste the 4 Python commands to your command line. Keep in mind that the tokenizer, the TRT-LLM engines, and the Triton model repository should be in a shared file storage between your nodes. They're required to launch your model in Triton. For example, if using AWS EFS, the values for `<PATH_TO_TOKENIZER>` and `<PATH_TO_ENGINES>` should be respect to the actutal EFS mount path. This is determined by your persistent-volume claim and mount path in chart/templates/deployment.yaml. Make sure that your nodes are able to access these files.

### d. Delete the pod

```
exit
kubectl delete -f multinode_helm_chart/setup_ssh_efs.yaml
```

## 3. Create `example_values.yaml` file for deployment

Make sure you go over the provided [`values.yaml`](./multinode_helm_chart/chart/values.yaml) first to understand what each value represents.

Below is the [`example_values.yaml`](./multinode_helm_chart/chart/example_values.yaml) file we use where `<EFS_MOUNT_PATH>=/var/run/models`:

```
gpu: NVIDIA-H100-80GB-HBM3
gpuPerNode: 8
persistentVolumeClaim: efs-claim

tensorrtLLM:
  parallelism:
    tensor: 8
    pipeline: 2

triton:
  image:
    name: ${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/triton_trtllm_multinode:24.08
  resources:
    cpu: 64
    memory: 512Gi
    efa: 32 # If you don't want to enable EFA, set this to 0.
  triton_model_repo_path: /var/run/models/tensorrtllm_backend/triton_model_repo
  enable_nsys: false # Note if you send lots of requests, nsys report can be very large.

logging:
  tritonServer:
    verbose: False

autoscaling:
  enable: true
  replicas:
    maximum: 2
    minimum: 1
  metric:
    name: triton:queue_compute:ratio
    value: 1
```

## 4. Install the Helm chart

```
helm install multinode-deployment \
  --values ./multinode_helm_chart/chart/values.yaml \
  --values ./multinode_helm_chart/chart/example_values.yaml \
  ./multinode_helm_chart/chart/.
```

In this example, we are going to deploy Triton server on 2 nodes with 8 GPUs each. This will result in having 2 pods running in your cluster. Command `kubectl get pods` should output something similar to below:

```
NAME                         READY   STATUS    RESTARTS   AGE
leaderworkerset-sample-0     1/1     Running   0          28m
leaderworkerset-sample-0-1   1/1     Running   0          28m
```

Use the following command to check Triton logs:

```
kubectl logs --follow leaderworkerset-sample-0
```

You should output something similar to below:

```
I0717 23:01:28.501008 300 server.cc:674] 
+----------------+---------+--------+
| Model          | Version | Status |
+----------------+---------+--------+
| ensemble       | 1       | READY  |
| postprocessing | 1       | READY  |
| preprocessing  | 1       | READY  |
| tensorrt_llm   | 1       | READY  |
+----------------+---------+--------+

I0717 23:01:28.501073 300 tritonserver.cc:2579] 
+----------------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Option                           | Value                                                                                                                                                                                                           |
+----------------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| server_id                        | rank0                                                                                                                                                                                                           |
| server_version                   | 2.47.0                                                                                                                                                                                                          |
| server_extensions                | classification sequence model_repository model_repository(unload_dependents) schedule_policy model_configuration system_shared_memory cuda_shared_memory binary_tensor_data parameters statistics trace logging |
| model_repository_path[0]         | /var/run/models/tensorrtllm_backend/triton_model_repo                                                                                                                                                          |
| model_control_mode               | MODE_NONE                                                                                                                                                                                                       |
| strict_model_config              | 1                                                                                                                                                                                                               |
| model_config_name                |                                                                                                                                                                                                                 |
| rate_limit                       | OFF                                                                                                                                                                                                             |
| pinned_memory_pool_byte_size     | 268435456                                                                                                                                                                                                       |
| cuda_memory_pool_byte_size{0}    | 67108864                                                                                                                                                                                                        |
| min_supported_compute_capability | 6.0                                                                                                                                                                                                             |
| strict_readiness                 | 1                                                                                                                                                                                                               |
| exit_timeout                     | 30                                                                                                                                                                                                              |
| cache_enabled                    | 0                                                                                                                                                                                                               |
+----------------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

I0717 23:01:28.502835 300 grpc_server.cc:2463] "Started GRPCInferenceService at 0.0.0.0:8001"
I0717 23:01:28.503047 300 http_server.cc:4692] "Started HTTPService at 0.0.0.0:8000"
I0717 23:01:28.544321 300 http_server.cc:362] "Started Metrics Service at 0.0.0.0:8002"
```

> [!Note]
> You may run into an error of `the GPU number is incompatible with 8 gpusPerNode when MPI size is 8`. The root cause is starting from v0.11.0, TRT-LLM backend checks the gpusPerNode parameter in the `config.json` file inside the output engines folder. This parameter is set during engine build time. If the value is the not the same as the number of GPUs in your node, this assertion error shows up. To resolve this, simply change the value in the file to match the number of GPUs in your node.

## 5. Send a curl POST request for infernce

In this AWS example, we can view the external IP address of Load Balancer by running `kubectl get services`. Note that we use `multinode_deployment` as helm chart installation name here. Your output should look something similar to below:

```
NAME                     TYPE           CLUSTER-IP      EXTERNAL-IP                                                              PORT(S)                                        AGE
kubernetes               ClusterIP      10.100.0.1      <none>                                                                   443/TCP                                        43d
leaderworkerset-sample   ClusterIP      None            <none>                                                                   <none>                                         54m
multinode-deployment     LoadBalancer   10.100.44.170   a69c447a535104f088d2e924f5523d41-634913838.us-east-1.elb.amazonaws.com   8000:32120/TCP,8001:32263/TCP,8002:31957/TCP   54m
```

You can send a CURL request to the `ensemble` TRT-LLM Llama-3.1 405B model hosted in Triton Server with the following command:

```
curl -X POST a69c447a535104f088d2e924f5523d41-634913838.us-east-1.elb.amazonaws.com:8000/v2/models/ensemble/generate -d '{"text_input": "What is machine learning?", "max_tokens": 64, "bad_words": "", "stop_words": "", "pad_id": 2, "end_id": 2}'
```

You should output similar to below:

```
{"context_logits":0.0,"cum_log_probs":0.0,"generation_logits":0.0,"model_name":"ensemble","model_version":"1","output_log_probs":[0.0,0.0,0.0,0.0,0.0],"sequence_end":false,"sequence_id":0,"sequence_start":false,"text_output":" Machine learning is a branch of artificial intelligence that deals with the development of algorithms that allow computers to learn from data and make predictions or decisions without being explicitly programmed. Machine learning algorithms are used in a wide range of applications, including image recognition, natural language processing, and predictive analytics.\nWhat is the difference between machine learning and"}
```

> [!Note]
> You may run into an error of `Multiple tagged security groups found for instance i-*************`. The root cause is both EKS cluster security group and EFA security group are using the same tag of `kubernetes.io/cluster/eks-cluster : owned`. This tag should only be attached to 1 security group, usually your main security group. To resolve this, simply delete the tag from the EFA security group.

## 6. Test Horizontal Pod Autoscaler and Cluster Autoscaler

To check HPA status, run:

```
kubectl get hpa multinode-deployment
```

You should output something similar to below:

```
NAME                   REFERENCE                                TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
multinode-deployment   LeaderWorkerSet/leaderworkerset-sample   0/1       1         2         1          66m
```

From the output above, the current metric value is 0 and the target value is 1. Note that in this example, our metric is a custom metric defined in Prometheus Rule. You can find more details in the [Install Prometheus rule for Triton metrics](./Configure_EKS_Cluster.md#8-install-prometheus-rule-for-triton-metrics) step. When the current value exceed 1, the HPA will start to create a new replica. We can either increase traffic by sending a large amount of requests to the LoadBalancer or manually increase minimum number of replicas to let the HPA create the second replica. In this example, we are going to choose the latter and run the following command:

```
kubectl patch hpa multinode-deployment -p '{"spec":{"minReplicas": 2}}'
```

Your `kubectl get pods` command should output something similar to below:

```
NAME                         READY   STATUS    RESTARTS   AGE
leaderworkerset-sample-0     1/1     Running   0          6h48m
leaderworkerset-sample-0-1   1/1     Running   0          6h48m
leaderworkerset-sample-1     0/1     Pending   0          13s
leaderworkerset-sample-1-1   0/1     Pending   0          13s
```

Here we can see the second replica is created but in `Pending` status. If you run `kubectl describe pod leaderworkerset-sample-1`, you should see events similar to below:

```
Events:
  Type     Reason            Age   From                Message
  ----     ------            ----  ----                -------
  Warning  FailedScheduling  48s   default-scheduler   0/3 nodes are available: 1 node(s) didn't match Pod's node affinity/selector, 2 Insufficient nvidia.com/gpu, 2 Insufficient vpc.amazonaws.com/efa. preemption: 0/3 nodes are available: 1 Preemption is not helpful for scheduling, 2 No preemption victims found for incoming pod.
  Normal   TriggeredScaleUp  15s   cluster-autoscaler  pod triggered scale-up: [{eks-efa-compute-ng-2-7ac8948c-e79a-9ad8-f27f-70bf073a9bfa 2->4 (max: 4)}]
```

The first event means that there are no available nodes to schedule any pods. This explains why the second 2 pods are in `Pending` status. The second event states that the Cluster Autoscaler detects that this pod is `unschedulable`, so it is going to increase number of nodes in our cluster until maximum is reached. You can find more details in the [Install Cluster Autoscaler](./Configure_EKS_Cluster.md#10-install-cluster-autoscaler) step. This process can take some time depending on whether AWS have enough nodes available to add to your cluster. Eventually, the Cluster Autoscaler will add 2 more nodes in your node group so that the 2 `Pending` pods can be scheduled on them. Your `kubectl get nodes` and `kubectl get pods` commands should output something similar to below:

```
NAME                             STATUS   ROLES    AGE   VERSION
ip-192-168-103-11.ec2.internal   Ready    <none>   15m   v1.30.2-eks-1552ad0
ip-192-168-106-8.ec2.internal    Ready    <none>   15m   v1.30.2-eks-1552ad0
ip-192-168-117-30.ec2.internal   Ready    <none>   11h   v1.30.2-eks-1552ad0
ip-192-168-127-31.ec2.internal   Ready    <none>   11h   v1.30.2-eks-1552ad0
ip-192-168-26-106.ec2.internal   Ready    <none>   11h   v1.30.2-eks-1552ad0
```

```
leaderworkerset-sample-0     1/1     Running   0          7h26m
leaderworkerset-sample-0-1   1/1     Running   0          7h26m
leaderworkerset-sample-1     1/1     Running   0          38m
leaderworkerset-sample-1-1   1/1     Running   0          38m
```

You can run the following command to change minimum replica back to 1:

```
kubectl patch hpa multinode-deployment -p '{"spec":{"minReplicas": 1}}'
```

The HPA will delete the second replica if current metric does not exceed the target value. The Cluster Autoscaler will also remove the added 2 nodes when it detects them as "free".

## 7. Uninstall the Helm chart

```
helm uninstall multinode-deployment
```

## 8. (Optional) NCCL Test

To test whether EFA is working properly, we can run a NCCL test across nodes. Make sure you modify the [nccl_test.yaml](/1.infrastructure/1_setup_cluster/multinode-triton-trtllm-inference/nccl_test.yaml) file and adjust the following values:

- `slotsPerWorker` : set to the number of GPUs per node in your cluster
- `-np` : set to "number_of_worker_nodes" * "number_of_gpus_per_node"
- `-N` : set to number_of_gpus_per_node
- `Worker: replicas` : set to number of worker pods you would like the test to run on. This must be less than or eaqual to the number of nodes in your cluster
- `node.kubernetes.io/instance-type` : set to the instance type of the nodes in your cluster against which you would like the nccl test to be run
- `nvidia.com/gpu` : set to the number of GPUs per node in your cluster, adjust in both the limits and requests section
- `vpc.amazonaws.com/efa` : set to the number of EFA adapters per node in your cluster, adjust in both the limits and requests section

Run the command below to deploy the MPI Operator which is required by the NCCL Test manifest:

```
kubectl apply --server-side -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.5.0/deploy/v2beta1/mpi-operator.yaml
```

Run the command below to deploy NCCL test:

```
kubectl apply -f nccl_test.yaml
```

Note that the launcher pod will keep restarting until the connection is established with the worker pods. Run the command below to see the launcher pod logs:

```
kubectl logs -f $(kubectl get pods | grep launcher | cut -d ' ' -f 1)
```

You should output something similar to below (example of 2 x p5.48xlarge):

```
[1,0]<stdout>:#                                                              out-of-place                       in-place          
[1,0]<stdout>:#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
[1,0]<stdout>:#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
[1,0]<stdout>:           8             2     float     sum      -1[1,0]<stdout>:    187.7    0.00    0.00      0[1,0]<stdout>:    186.7    0.00    0.00      0
[1,0]<stdout>:          16             4     float     sum      -1[1,0]<stdout>:    186.5    0.00    0.00      0[1,0]<stdout>:    186.5    0.00    0.00      0
[1,0]<stdout>:          32             8     float     sum      -1[1,0]<stdout>:    186.4    0.00    0.00      0[1,0]<stdout>:    186.9    0.00    0.00      0
[1,0]<stdout>:          64            16     float     sum      -1[1,0]<stdout>:    186.0    0.00    0.00      0[1,0]<stdout>:    186.7    0.00    0.00      0
[1,0]<stdout>:         128            32     float     sum      -1[1,0]<stdout>:    186.8    0.00    0.00      0[1,0]<stdout>:    186.7    0.00    0.00      0
[1,0]<stdout>:         256            64     float     sum      -1[1,0]<stdout>:    186.5    0.00    0.00      0[1,0]<stdout>:    187.1    0.00    0.00      0
[1,0]<stdout>:         512           128     float     sum      -1[1,0]<stdout>:    187.1    0.00    0.01      0[1,0]<stdout>:    186.0    0.00    0.01      0
[1,0]<stdout>:        1024           256     float     sum      -1[1,0]<stdout>:    188.4    0.01    0.01      0[1,0]<stdout>:    187.1    0.01    0.01      0
[1,0]<stdout>:        2048           512     float     sum      -1[1,0]<stdout>:    190.6    0.01    0.02      0[1,0]<stdout>:    189.9    0.01    0.02      0
[1,0]<stdout>:        4096          1024     float     sum      -1[1,0]<stdout>:    194.4    0.02    0.04      0[1,0]<stdout>:    194.0    0.02    0.04      0
[1,0]<stdout>:        8192          2048     float     sum      -1[1,0]<stdout>:    200.4    0.04    0.08      0[1,0]<stdout>:    201.3    0.04    0.08      0
[1,0]<stdout>:       16384          4096     float     sum      -1[1,0]<stdout>:    215.5    0.08    0.14      0[1,0]<stdout>:    215.4    0.08    0.14      0
[1,0]<stdout>:       32768          8192     float     sum      -1[1,0]<stdout>:    248.9    0.13    0.25      0[1,0]<stdout>:    248.7    0.13    0.25      0
[1,0]<stdout>:       65536         16384     float     sum      -1[1,0]<stdout>:    249.4    0.26    0.49      0[1,0]<stdout>:    248.6    0.26    0.49      0
[1,0]<stdout>:      131072         32768     float     sum      -1[1,0]<stdout>:    255.3    0.51    0.96      0[1,0]<stdout>:    254.6    0.51    0.97      0
[1,0]<stdout>:      262144         65536     float     sum      -1[1,0]<stdout>:    265.6    0.99    1.85      0[1,0]<stdout>:    264.5    0.99    1.86      0
[1,0]<stdout>:      524288        131072     float     sum      -1[1,0]<stdout>:    327.1    1.60    3.00      0[1,0]<stdout>:    327.3    1.60    3.00      0
[1,0]<stdout>:     1048576        262144     float     sum      -1[1,0]<stdout>:    432.8    2.42    4.54      0[1,0]<stdout>:    431.8    2.43    4.55      0
[1,0]<stdout>:     2097152        524288     float     sum      -1[1,0]<stdout>:    616.5    3.40    6.38      0[1,0]<stdout>:    614.0    3.42    6.40      0
[1,0]<stdout>:     4194304       1048576     float     sum      -1[1,0]<stdout>:    895.2    4.69    8.79      0[1,0]<stdout>:    893.4    4.70    8.80      0
[1,0]<stdout>:     8388608       2097152     float     sum      -1[1,0]<stdout>:   1512.3    5.55   10.40      0[1,0]<stdout>:   1506.1    5.57   10.44      0
[1,0]<stdout>:    16777216       4194304     float     sum      -1[1,0]<stdout>:   1669.5   10.05   18.84      0[1,0]<stdout>:   1667.3   10.06   18.87      0
[1,0]<stdout>:    33554432       8388608     float     sum      -1[1,0]<stdout>:   2021.6   16.60   31.12      0[1,0]<stdout>:   2021.1   16.60   31.13      0
[1,0]<stdout>:    67108864      16777216     float     sum      -1[1,0]<stdout>:   2879.7   23.30   43.69      0[1,0]<stdout>:   2897.5   23.16   43.43      0
[1,0]<stdout>:   134217728      33554432     float     sum      -1[1,0]<stdout>:   4694.8   28.59   53.60      0[1,0]<stdout>:   4699.9   28.56   53.55      0
[1,0]<stdout>:   268435456      67108864     float     sum      -1[1,0]<stdout>:   7858.8   34.16   64.05      0[1,0]<stdout>:   7868.3   34.12   63.97      0
[1,0]<stdout>:   536870912     134217728     float     sum      -1[1,0]<stdout>:    14105   38.06   71.37      0[1,0]<stdout>:    14109   38.05   71.35      0
[1,0]<stdout>:  1073741824     268435456     float     sum      -1[1,0]<stdout>:    26780   40.10   75.18      0[1,0]<stdout>:    26825   40.03   75.05      0
[1,0]<stdout>:  2147483648     536870912     float     sum      -1[1,0]<stdout>:    52101   41.22   77.28      0[1,0]<stdout>:    52130   41.19   77.24      0
[1,0]<stdout>:  4294967296    1073741824     float     sum      -1[1,0]<stdout>:   102771   41.79   78.36      0[1,0]<stdout>:   102725   41.81   78.39      0
[1,0]<stdout>:  8589934592    2147483648     float     sum      -1[1,0]<stdout>:   204078   42.09   78.92      0[1,0]<stdout>:   204089   42.09   78.92      0
[1,0]<stdout>:# Out of bounds values : 0 OK
[1,0]<stdout>:# Avg bus bandwidth    : 20.2958
```

## 9. (Optional) GenAI-Perf

GenAI-Perf is a benchmarking tool for Triton server to measure latency and throughput of LLMs. We provide an example here.

### a. Modify the `gen_ai_perf.yaml` file

Adjust the following values in [gen_ai_perf.yaml](./multinode_helm_chart/gen_ai_perf.yaml) file:

- `image` : change image tag. Default is 24.08 which supports TRT-LLM v0.12.0
- `claimName` : set to your EFS pvc name

### b. Run benchmark

Run the below command to start a Triton server SDK container:

```
kubectl apply -f gen_ai_perf.yaml
kubectl exec -it gen-ai-perf -- bash
```

Run the below command to start benchmarking:

```
genai-perf profile \
  -m ensemble \
  --service-kind triton \
  --backend tensorrtllm \
  --num-prompts 100 \
  --random-seed 123 \
  --synthetic-input-tokens-mean 32768 \
  --synthetic-input-tokens-stddev 0 \
  --streaming \
  --output-tokens-mean 1024 \
  --output-tokens-stddev 0 \
  --output-tokens-mean-deterministic \
  --tokenizer hf-internal-testing/llama-tokenizer \
  --concurrency 1 \
  --measurement-interval 10000 \
  --url a69c447a535104f088d2e924f5523d41-634913838.us-east-1.elb.amazonaws.com:8001 \
  -- --request-count=1
```

You should output something similar to below. These numbers are just for example purposes and not representative of peak performance.

```
                                               LLM Metrics                                                
| Statistic                 | avg        | min        | max        | p99        | p90        | p75        |
|---------------------------|------------|------------|------------|------------|------------|------------|
| Time to first token (ms)  | 847.16     | 825.78     | 853.19     | 853.17     | 852.93     | 852.69     |
| Inter token latency (ms)  | 48.22      | 48.19      | 48.25      | 48.25      | 48.25      | 48.25      |
| Request latency (ms)      | 50,176.83  | 50,147.34  | 50,216.11  | 50,215.92  | 50,214.18  | 50,205.07  |
| Output sequence length    | 1,024.00   | 1,024.00   | 1,024.00   | 1,024.00   | 1,024.00   | 1,024.00   |
| Input sequence length     | 1,024.00   | 1,023.00   | 1,025.00   | 1,025.00   | 1,025.00   | 1,024.00   |

Output token throughput (per sec): 20.41
```
