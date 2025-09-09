# NeuronX Distributed Inference on EKS

This example demonstrates deploying Large Language Models using **NeuronX Distributed Inference (NxDI)** on Amazon EKS with AWS Trainium instances. The deployment supports both standard inference and speculative decoding with prefix caching across both

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Amazon EKS Cluster                       │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  Download Job   │  │   Compilation   │  │   Monitoring │ │
│  │  (HF → EFS)     │  │      Job        │  │   DaemonSet  │ │
│  │  • Target model │  │  • NxDI compile │  │  • Neuron    │ │
│  │  • Draft model  │  │  • Spec / NoSpec│  │    Monitor   │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│                                                             │
│  ┌─────────────────┐                                        │
│  │  Inference      │                                        │
│  │  Deployment     │                                        │
│  │  • vLLM Server  │                                        │
│  │  • LoadBalancer │                                        │
│  └─────────────────┘                                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Shared EFS Storage                         ││
│  │  • /shared/model_hub/* (downloads)                      ││
│  │  • /shared/compiled_models/Qwen3-32B/* (neffs)          ││
│  │  • Logs                                                 ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Kubernetes-native** jobs for **download** and **compile**
- **Speculative decoding** toggle via `ENABLE_SPECULATIVE`
- **Separate compiled outputs** for spec / non-spec (no overwrites)
- **Shared EFS storage** for models, artifacts, and logs
- **Load balancing** and **monitoring** with Neuron Monitor

## Prerequisites

- `kubectl`, `aws` CLI, and `helm`
- EKS cluster with Trainium nodes and EFS PVC
- A Hugging Face token with access to the target repos

Install Neuron device plugin and (optionally) the scheduler extension:

```bash
helm upgrade --install neuron-helm-chart oci://public.ecr.aws/neuron/neuron-helm-chart --set "npd.enabled=false"
kubectl get ds neuron-device-plugin -n kube-system

helm upgrade --install neuron-helm-chart oci://public.ecr.aws/neuron/neuron-helm-chart \
  --set "scheduler.enabled=true" \
  --set "npd.enabled=false"
```

## Setup

### 1) Clone & Navigate

```bash
git clone https://github.com/aws-samples/awsome-inference.git
cd awsome-inference/2.projects/neuronx-distributed/nxd-inference-eks/
```

### 2) Label Trainium Nodes

```bash
kubectl label nodes -l node.kubernetes.io/instance-type=trn1.32xlarge workload-type=neuron-inference
kubectl taint nodes -l node.kubernetes.io/instance-type=trn1.32xlarge aws.amazon.com/neuron=:NoSchedule
kubectl get nodes -L workload-type,node.kubernetes.io/instance-type
```

### 3) Namespace, Storage, and Secrets

```bash
kubectl create namespace neuron-inference

# Apply EFS storage configuration
kubectl apply -f fused-SD/manifests/storage.yaml -n neuron-inference

# Create HF token secret once
# replace YOUR_HF_TOKEN with your actual token (starts with hf_)
kubectl -n neuron-inference create secret generic hf-token \
  --from-literal=HF_TOKEN='YOUR_HF_TOKEN' \
  --dry-run=client -o yaml | kubectl apply -f -

```

## Configuration

Use an env file to keep things tidy (example shows Qwen3-32B target + Qwen3-0.6B draft):

```bash
cat > fused-SD/.env <<'EOF'
# HF
HF_MODEL_ID=Qwen/Qwen2.5-32B-Instruct
HF_DRAFT_MODEL_ID=Qwen/Qwen2.5-0.5B-Instruct

# Paths (EFS)
MODEL_ROOT=/shared/model_hub
MODEL_DIRNAME=Qwen3-32B
DRAFT_DIRNAME=Qwen3-0.6B
COMPILED_ROOT=/shared/compiled_models/Qwen3-32B

# NxDI compile
ENABLE_SPECULATIVE=false
SPECULATION_LENGTH=7
TP_DEGREE=32
BATCH_SIZE=1
SEQ_LEN=8192
MAX_CONTEXT_LEN=8192
EOF

source fused-SD/.env
```

## Workflow

> **Two steps:** (1) **Download** both models to EFS, (2) **Compile** with or without speculation.  
> Compiles write to **separate directories** so you can keep both.

### Create a secret once for your HF token:

kubectl -n neuron-inference create secret generic hf-token \
  --from-literal=HF_TOKEN='YOUR_HF_TOKEN'


### Step 1 — Download both models (target + draft)

Apply the **download job** manifest:

```bash
kubectl apply -n neuron-inference -f fused-SD/manifests/model_download.yaml
kubectl -n neuron-inference wait --for=condition=complete job/neuron-model-download --timeout=3600s
kubectl -n neuron-inference logs job/neuron-model-download --tail=200
```

Expected locations after success:

```
/shared/model_hub/${MODEL_DIRNAME}/config.json
/shared/model_hub/${DRAFT_DIRNAME}/config.json
```

Quick verify:

```bash
kubectl -n neuron-inference exec -it <any-running-pod> -- ls -l /shared/model_hub/${MODEL_DIRNAME} | head
```

### Step 2 — Compile (separate outputs for spec vs non-spec)

Apply the **compile job** manifest. Control speculation by editing the `ENABLE_SPECULATIVE` environment variable in the manifest:

```bash
# Non-spec compile (kept in /shared/compiled_models/Llama-3.3-70B/nospec_tp32)
kubectl apply -n neuron-inference -f fused-SD/manifests/compile.yaml
kubectl -n neuron-inference wait --for=condition=complete job/neuron-model-compilation --timeout=3600s
kubectl -n neuron-inference logs job/neuron-model-compilation --tail=200

# For speculative compile, edit the manifest to set ENABLE_SPECULATIVE=true, then:
kubectl -n neuron-inference delete job neuron-model-compilation --ignore-not-found
kubectl apply -n neuron-inference -f fused-SD/manifests/compile.yaml
kubectl -n neuron-inference wait --for=condition=complete job/neuron-model-compilation --timeout=3600s
kubectl -n neuron-inference logs job/neuron-model-compilation --tail=200
```

**Output layout (no overwrites):**
```
/shared/compiled_models/Qwen3-32B/
  ├─ nospec_tp32/
  └─ spec_slen7_tp32/
```

### Step 3 — Deploy Inference

Point your inference deployment at the compiled directory you want:

- Non-spec: `/shared/compiled_models/Qwen3-32B/nospec_tp32`
- Spec: `/shared/compiled_models/Qwen3-32B/spec_slen7_tp32`

Apply your inference deployment/service manifests and wait for readiness, then test via port-forward or load balancer as usual.

## Troubleshooting

**Downloads didn’t happen**
- Check the download job logs:
  ```bash
  kubectl -n neuron-inference logs job/neuron-model-download --tail=200
  ```
- Ensure the HF token secret exists and is referenced:
  ```bash
  kubectl -n neuron-inference get secret hf-token
  ```
- Verify the EFS PVC is bound and writable:
  ```bash
  kubectl -n neuron-inference get pvc
  ```

**Compile fails immediately saying “Unrecognized model … config.json”**
- The download likely didn’t complete or the path is wrong. Verify:
  ```bash
  kubectl -n neuron-inference exec -it <pod> -- test -f /shared/model_hub/${MODEL_DIRNAME}/config.json && echo OK
  ```

**Spec compile overwrote non-spec?**
- With the provided manifests, outputs are separated per mode (`nospec_*` vs `spec_*`). If you see overwrites, confirm your `COMPILED_ROOT` and job env vars.

**Neuron compiler errors**
- These are model/hardware/SDK specific. Re-run with smaller `TP_DEGREE`, confirm SDK image version, or inspect `/shared/compile*.log`. Consider filing an issue with logs.

## Cleanup

```bash
kubectl -n neuron-inference delete job neuron-model-download --ignore-not-found
kubectl -n neuron-inference delete job neuron-model-compilation --ignore-not-found
kubectl -n neuron-inference delete deployment neuron-llama-inference service neuron-llama-service --ignore-not-found
kubectl -n neuron-inference delete pvc efs-models-pvc --ignore-not-found
kubectl delete namespace neuron-inference
```

## References

- [AWS Neuron Documentation](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/) – NxDI & compiler guidance
- [NeuronX Distributed Inference Guide](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/neuronx-distributed/index.html)
- [vLLM Documentation](https://docs.vllm.ai/) – Server flags and deployment considerations
- [Kubernetes Jobs Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [AWS Neuron Helm Charts](https://github.com/aws-neuron/aws-neuron-helm-charts)
- [AWS Trainium Instance Types](https://aws.amazon.com/ec2/instance-types/trn1/)
