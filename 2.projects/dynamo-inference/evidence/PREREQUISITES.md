# Cluster prerequisites for pr72-rev8 experiments

Anything in this campaign assumes the following are already in place. If
your cluster lacks any of these, install them first — these are NOT
captured per-experiment because they're shared across the entire campaign.

## 1. Hardware

- **EKS cluster** with at least 2 SageMaker HyperPod-managed nodes
  (p5.48xlarge or p5en.48xlarge — the campaign was validated on p5.48xlarge)
- Each node: 8× H100 80GB SXM5, 32× EFA NICs (vpc.amazonaws.com/efa = 32)
- Region: us-east-2 (the campaign-issued ECR + CodeBuild are in us-east-2)
- Network: HyperPod-default VPC. **Do not use secondary VPC CIDRs** — EFA
  SRD silently drops on secondary CIDRs. Stay on primary CIDR only.

## 2. Required cluster-level installs

### 2.1 Dynamo Operator (provides the `nvidia.com/v1alpha1` `DynamoGraphDeployment` CRD)

```bash
helm repo add ai-dynamo https://helm.ngc.nvidia.com/nvidia/ai-dynamo
helm repo update
helm install dynamo-platform ai-dynamo/dynamo-platform \
  --namespace default \
  --version 1.1.0
```

Verify:
```bash
kubectl get crd dynamographdeployments.nvidia.com
# expected: present, established=True
kubectl get pod -n default -l app.kubernetes.io/name=dynamo-operator
# expected: dynamo-platform-dynamo-operator-controller-manager-* Running 1/1
```

### 2.2 ETCD service (used for NIXL coordination + Dynamo runtime metadata)

Installed automatically by the helm chart above as
`dynamo-platform-etcd-0` StatefulSet pod with service
`dynamo-platform-etcd.default.svc.cluster.local:2379`.

Verify:
```bash
kubectl get svc dynamo-platform-etcd -n default
# expected: ClusterIP, port 2379
```

### 2.3 NATS JetStream (used for KV router events transport)

Also installed by the helm chart as `dynamo-platform-nats-0` with service
`dynamo-platform-nats.default.svc.cluster.local:4222`.

Verify:
```bash
kubectl get svc dynamo-platform-nats -n default
# expected: ClusterIP, port 4222
```

### 2.4 NVIDIA device plugin + EFA device plugin

Required for `nvidia.com/gpu` and `vpc.amazonaws.com/efa` resource quotas.
HyperPod EKS pre-installs these. Verify:
```bash
kubectl get nodes -o json | jq '.items[].status.allocatable | {gpu: ."nvidia.com/gpu", efa: ."vpc.amazonaws.com/efa"}' \
  | head -10
# expected per node: gpu="8", efa="32"
```

### 2.5 GDRCopy + efa_nv_peermem kernel modules

Required for GPU-direct RDMA (otherwise EFA bounces through CPU memory).
The `gdrcopy-installer-v2-*` and `efa-nv-peermem-loader-*` DaemonSets
must be Running on every GPU node:

```bash
kubectl get pod -n default -l name=gdrcopy-installer-v2 -o wide
kubectl get pod -n default -l name=efa-nv-peermem-loader -o wide
```

### 2.6 FSx for Lustre PVC (for Hugging Face model cache)

```bash
kubectl get pvc dynamo-shared-storage -n default
# expected: Bound, ReadWriteMany
```

If FSx isn't available, every DGD manifest in this campaign can be edited
to swap the volume from `persistentVolumeClaim` to `emptyDir`, but model
loads will redownload from HF every pod restart (~10 min added cold time).

## 3. Required secrets

### 3.1 hf-token (Hugging Face access token)

The model `meta-llama/Llama-3.1-8B-Instruct` is gated; the worker pods
read both `HF_TOKEN` and `HUGGING_FACE_HUB_TOKEN` env vars.

```bash
kubectl create secret generic hf-token -n default \
  --from-literal=HF_TOKEN="<your-hf-token>" \
  --from-literal=HUGGING_FACE_HUB_TOKEN="<your-hf-token>"
```

**HARD GOTCHA:** A secret with only the `token` key is insufficient.
Both `HF_TOKEN` and `HUGGING_FACE_HUB_TOKEN` must be present, otherwise
the Frontend hits HF 401 on `USE_POLICY.md` (see rev6 root cause).

### 3.2 ECR credentials

The cluster's node IAM role must have `AmazonEC2ContainerRegistryReadOnly`
or equivalent for the `${ECR_REGISTRY}`
account. HyperPod default role usually has this.

## 4. Cluster lock (multi-engineer coordination)

This campaign used a per-cluster lock at
`~/.claude/cluster-lock-h100.json`. Any engineer running the
experiments must claim the lock before deploying:

```bash
cat > ~/.claude/cluster-lock-h100.json <<EOF
{
  "holder": "$(whoami)-pr72-rev8-replay",
  "claimed_at": "$(date -u +%FT%TZ)",
  "released_at": null,
  "timeout_minutes": 60,
  "purpose": "reproducing pr72-rev8 campaign experiments",
  "queue": []
}
EOF
```

Release after each session by setting `holder: null` and
`released_at: <now>`.

## 5. CLI tools

- `kubectl` v1.28+
- `aws` CLI v2 (for CodeBuild + ECR)
- `helm` v3.x
- `yq` v4 (for manifest queries)
- `python3` 3.10+ (for the multi-node bench scripts)

## 6. Verification — full preflight in one command

```bash
kubectl get nodes -l node.kubernetes.io/instance-type=ml.p5.48xlarge --no-headers \
  | wc -l                       # expect ≥ 2
kubectl get crd dynamographdeployments.nvidia.com -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' \
                                # expect "True"
kubectl get svc dynamo-platform-etcd -n default -o jsonpath='{.spec.ports[0].port}'    # expect "2379"
kubectl get svc dynamo-platform-nats -n default -o jsonpath='{.spec.ports[0].port}'    # expect "4222"
kubectl get secret hf-token -n default -o json | jq -r '.data | keys[]' | sort         # expect HF_TOKEN, HUGGING_FACE_HUB_TOKEN
kubectl get pvc dynamo-shared-storage -n default -o jsonpath='{.status.phase}'         # expect "Bound"
```

If all 6 lines return the expected values, you're ready to run any
experiment in this campaign.
