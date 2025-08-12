# NeuronX Distributed Inference on EKS

This example demonstrates deploying Large Language Models using **NeuronX Distributed Inference (NxDI)** on Amazon EKS with AWS Trainium instances. The deployment supports both standard inference and speculative decoding for improved performance.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Amazon EKS Cluster                       │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   Compilation   │  │   Inference     │  │   Monitoring │ │
│  │      Job        │  │   Deployment    │  │   DaemonSet  │ │
│  │                 │  │                 │  │              │ │
│  │ • Model Download│  │ • vLLM Server   │  │ • Neuron     │ │
│  │ • NxDI Compile  │  │ • Load Balancer │  │   Monitor    │ │
│  │ • Optimization  │  │ • Auto-scaling  │  │ • Metrics    │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Shared EFS Storage                         ││
│  │  • Model artifacts  • Compiled models  • Logs           ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Kubernetes-native deployment** with auto-scaling capabilities
- **Speculative decoding support** for improved latency
- **Shared EFS storage** for model artifacts and compiled models
- **Load balancing** with Kubernetes services
- **Monitoring and observability** with Neuron Monitor
- **Easy configuration switching** between standard and speculative modes

## Prerequisites

### 1. Infrastructure Setup

Before deploying the NXD inference service, ensure you have:

1. **VPC Setup**: Deploy the VPC using the provided CloudFormation template:
   ```bash
   aws cloudformation create-stack \
     --stack-name neuron-vpc \
     --template-body file://awsome-inference/1.infrastructure/0_setup_vpc/trn-vpc-example.yaml
   ```

2. **EKS Cluster**: Create the EKS cluster with Trainium nodes:
   ```bash
   eksctl create cluster -f awsome-inference/1.infrastructure/1_setup_cluster/nxd-inference/trn1-nxd-cluster-config.yaml
   ```

3. **EFS Setup**: Follow the EFS setup instructions in the cluster creation guide.

### 2. Required Tools

- `kubectl` configured for your EKS cluster
- `envsubst` for template substitution
- `aws` CLI configured with appropriate permissions

### 3. Access Requirements

- **HuggingFace Token**: Required for downloading gated models like Llama
- **Container Registry Access**: Ensure nodes can pull from public ECR

## Configuration

### Environment Variables

The deployment is configured through the `.env` file. Copy and customize it:

```bash
cp .env.example .env
```

Key configuration options:

```bash
# Hugging Face Configuration
HF_TOKEN=your_huggingface_token_here
HF_MODEL_ID=meta-llama/Llama-3.3-70B-Instruct
HF_DRAFT_MODEL_ID=meta-llama/Llama-3.2-1B-Instruct
MODEL_NAME=llama-3-70B-inst

# Inference Configuration
MAX_MODEL_LEN=12800
SEQ_LEN=12800
MAX_CONTEXT_LEN=12288

# Neuron Configuration
TENSOR_PARALLEL_SIZE=32
TP_DEGREE=32
NAMESPACE=neuron-inference
BATCH_SIZE=1
MAX_NUM_SEQS=1

# Speculative Decoding Configuration
ENABLE_SPECULATIVE=false  # Set to true to enable speculative decoding
SPECULATION_LENGTH=7

# Storage Paths
MODEL_PATH=/shared/models/Llama-3.3-70B-Instruct
COMPILED_MODEL_PATH=/shared/traced_model/Llama-3.3-70B-Instruct
DRAFT_MODEL_PATH=/shared/models/Llama-3.2-1B-Instruct
```

## Deployment Guide

### Step 1: Create Namespace and Storage

```bash
# Create namespace
kubectl create namespace $NAMESPACE

# Apply EFS storage configuration
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-models-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 500Gi
EOF
```

### Initial Deployment (Without Speculation)
```
# 1. Make sure ENABLE_SPECULATIVE=false in .env
vim .env  # Set ENABLE_SPECULATIVE=false

# 2. Load env vars and deploy
source .env
kubectl create namespace $NAMESPACE

# 3. Apply storage (if not already done)
envsubst < storage.template.yaml | kubectl apply -f -

# 4. Compile model
envsubst < compile.template.yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/neuron-model-compilation -n $NAMESPACE --timeout=3600s

# 5. Deploy inference server
envsubst < deployment.template.yaml | kubectl apply -f -
kubectl wait --for=condition=available deployment/neuron-llama-inference -n $NAMESPACE --timeout=600s

# 6. Check status
kubectl get all -n $NAMESPACE
```
### Compile for and Enable FSD (Fused SD)

```
# 1. Update .env to enable speculation
vim .env  # Change ENABLE_SPECULATIVE=true

# 2. Reload env vars
source .env

# 3. Delete old compilation
kubectl delete job neuron-model-compilation -n $NAMESPACE

# 4. Recompile with speculation enabled
envsubst < compile.template.yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/neuron-model-compilation -n $NAMESPACE --timeout=3600s

# 5. Update deployment
envsubst < deployment.template.yaml | kubectl apply -f -

# 6. Restart deployment to pick up changes
kubectl rollout restart deployment/neuron-llama-inference -n $NAMESPACE
kubectl wait --for=condition=available deployment/neuron-llama-inference -n $NAMESPACE --timeout=600s
```

### Switch back to standard 

```
# 1. Update .env
vim .env  # Change ENABLE_SPECULATIVE=false

# 2. Reload and recompile
source .env
kubectl delete job neuron-model-compilation -n $NAMESPACE
envsubst < compile.template.yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/neuron-model-compilation -n $NAMESPACE --timeout=3600s

# 3. Update deployment
envsubst < deployment.template.yaml | kubectl apply -f -
kubectl rollout restart deployment/neuron-llama-inference -n $NAMESPACE
```

### Example Usage

```
# Check compilation logs
kubectl logs -l job-name=neuron-model-compilation -n $NAMESPACE --tail=100

# Check deployment logs
kubectl logs deployment/neuron-llama-inference -n $NAMESPACE --tail=100

# Port forward for testing
kubectl port-forward service/neuron-llama-service 8000:8000 -n $NAMESPACE

# Test inference
curl -X POST http://localhost:8000/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model": "'$MODEL_PATH'", "prompt": "Hello", "max_tokens": 50}'
```

## Cleanup

```bash
# Delete the deployment
kubectl delete -f fused-SD/manifests/fsd-deploy.yaml
kubectl delete -f fused-SD/manifests/compile.yaml

# Delete the namespace
kubectl delete namespace $NAMESPACE

# Delete monitoring
kubectl delete namespace neuron-monitor
```

## Support and Resources

- [AWS Neuron Documentation](https://awsdocs-neuron.readthedocs-hosted.com/)
- [NeuronX Distributed Inference Guide](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/nxd-inference/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)