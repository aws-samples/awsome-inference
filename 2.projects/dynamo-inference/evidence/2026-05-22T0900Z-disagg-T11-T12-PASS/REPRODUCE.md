# Round 6 — Reproduce: T11 + T12 disaggregated inference on rev8

**Goal:** Reproduce a successful end-to-end disaggregated inference (Frontend +
PrefillWorker + DecodeWorker, cross-node) on the rev8 image with KV cache
transfer over NIXL LIBFABRIC. T11 = `/v1/models`, T12 = `/v1/completions`.

## 1. Environment

| Item | Value |
|---|---|
| Date of run | 2026-05-22 ~10:25–10:35 UTC |
| Cluster | EKS HyperPod, p5.48xlarge × 2 (H100, 8 GPU + 32 EFA/node) |
| Image SHA | `${ECR_REGISTRY}/dynamo-efa:520cfc584abb` |
| Source commit | `520cfc5` |
| Model | `meta-llama/Llama-3.1-8B-Instruct` (loaded from FSx HF cache `/shared/hf_cache`) |
| Dynamo runtime | 1.1.0 |
| vLLM | shipped with Dynamo 1.1.0 (NixlConnector w/ kv_role=kv_both) |
| Frontend node | hyperpod-i-0be4f4fecf22a73b3 (10.1.3.82) |
| PrefillWorker node | hyperpod-i-0be4f4fecf22a73b3 (10.1.3.151) |
| DecodeWorker node | hyperpod-i-0a3eb6d3953cceaa7 (10.1.3.73) — cross-node |

## 2. Prerequisites

- Image `dynamo-efa:520cfc584abb` already in ECR (see round 5 REPRODUCE.md if not).
- Dynamo Operator installed (provides `nvidia.com/v1alpha1` DGD CRD).
- `dynamo-platform-etcd` and `dynamo-platform-nats` Pods Running in `default` ns.
- FSx PVC `dynamo-shared-storage` mounted (or override to `emptyDir` in YAML).
- Secret `hf-token` with `HF_TOKEN` and `HUGGING_FACE_HUB_TOKEN` keys.
- H100 cluster lock claimed.

## 3. Manifest

Base file: `/tmp/awsome-inference-1/2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml`
(in PR #72 fork at commit `520cfc5`).

The only edit needed for round 6 reproduction was the image SHA substitution:

```bash
EVIDENCE_DIR=$(pwd)/docs/evidence/rev8-pr72-e2e-2026-05-21/round6-disagg-T11-T12
mkdir -p "$EVIDENCE_DIR"
sed 's|dynamo-efa:9467d1460c71|dynamo-efa:520cfc584abb|g' \
  /tmp/awsome-inference-1/2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml \
  > "$EVIDENCE_DIR/01-dgd-as-deployed.yaml"
```

Critical inline fragments in the manifest:

**Frontend** (1 replica, no GPU):
```bash
exec python3 -m dynamo.frontend --http-port 8000 --http-host 0.0.0.0
```
ENV: `DYNAMO_BACKEND=vllm`, `ETCD_ENDPOINTS`, `NATS_SERVER`, `DYN_SYSTEM_ENABLED=true`.

**PrefillWorker** (1 replica, 1 GPU + 1 EFA + hugepages):
```bash
unset HPCX_DIR HPCX_MPI_DIR HPCX_HOME HPCX_UCX_DIR ...
source /opt/dynamo/venv/bin/activate
exec python3 -m dynamo.vllm \
  --model meta-llama/Llama-3.1-8B-Instruct \
  --served-model-name meta-llama/Llama-3.1-8B-Instruct \
  --disaggregation-mode prefill \
  --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both","kv_connector_extra_config":{"backends":["LIBFABRIC"]}}' \
  --max-model-len 4096 \
  --gpu-memory-utilization 0.85
```
ENV: `NIXL_BACKEND=LIBFABRIC`, `NIXL_LIBFABRIC_MAX_RAILS=1`, `VLLM_NIXL_KVCACHE_BACKEND=LIBFABRIC`,
`FI_PROVIDER=efa`, `FI_EFA_USE_DEVICE_RDMA=1`, `FI_EFA_ENABLE_SHM=0`, `FI_EFA_ENABLE_SHM_TRANSFER=0`,
`HF_HOME=/shared/hf_cache`, `VLLM_NIXL_SIDE_CHANNEL_HOST` from `status.podIP`,
`VLLM_NIXL_SIDE_CHANNEL_PORT=5700`.

`readinessProbe`:
```yaml
httpGet: { path: /health, port: 9090 }
initialDelaySeconds: 120
periodSeconds: 10
timeoutSeconds: 5
failureThreshold: 60
```

(Without this probe, EndpointSlice stays ready=False during model load and Frontend's
KubeDiscoveryClient returns 0 instances — root cause of the rev6 T12 hang. See
`docs/evidence/multinode-2026-05-06-rev5/`.)

**DecodeWorker** identical to PrefillWorker except `--disaggregation-mode decode` and
`anti-affinity` to PrefillWorker by `kubernetes.io/hostname` (forces cross-node placement).

## 4. Deploy

```bash
kubectl apply -f "$EVIDENCE_DIR/01-dgd-as-deployed.yaml" 2>&1 | tee "$EVIDENCE_DIR/02-apply.log"
# expected: dynamographdeployment.nvidia.com/dynamo-combined-vllm created
```

## 5. Wait for 3/3 pods Ready

```bash
for i in $(seq 1 90); do
  PODS=$(kubectl get pods -n default \
    -l "nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm" \
    -o jsonpath='{range .items[*]}{.metadata.name}={.status.phase}/{.status.containerStatuses[0].ready};{end}')
  RDY=$(echo "$PODS" | tr ';' '\n' | grep -c "=Running/true")
  echo "$(date -u +%H:%M:%SZ) ready=$RDY/3"
  [ "$RDY" -ge 3 ] && break
  sleep 10
done
kubectl get pods -n default -l nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm -o wide \
  > "$EVIDENCE_DIR/03-pods.txt"
```

Round 6 timeline: pods Pending → ContainerCreating → Running/false (loading model) →
Running/true at ~3 min after apply. Frontend reaches Ready ~30s before workers.

**CRITICAL label selector:** `nvidia.com/dynamo-graph-deployment-name=<dgd-name>`.
NOT `app.kubernetes.io/part-of` — the operator strips that. Round 7 first attempt
wasted 40 min on the wrong selector.

## 6. T11 — /v1/models

```bash
SVC=$(kubectl get svc -n default dynamo-combined-vllm-frontend -o jsonpath='{.spec.clusterIP}')
echo "Frontend SVC: $SVC:8000"

kubectl run curl-tester --rm -i --restart=Never --image=curlimages/curl:latest -n default --quiet --command -- \
  curl -sS http://$SVC:8000/v1/models > "$EVIDENCE_DIR/04-models.json"
cat "$EVIDENCE_DIR/04-models.json"
```

Expected:
```json
{"object":"list","data":[{"id":"meta-llama/Llama-3.1-8B-Instruct","object":"model","created":1779445863,"owned_by":"nvidia","context_window":4096}]}
```

If `/v1/models` returns empty `data`: Frontend's KubeDiscoveryClient hasn't seen the
workers. Check `nvidia.com/dynamo-namespace` label on worker pods matches what Frontend
queries (will be `default-dynamo-combined-vllm-<hash>`). The operator stamps a per-DGD
namespace; cross-DGD service discovery does not work.

## 7. T12 — /v1/completions cross-node disagg

```bash
MODEL=$(python3 -c "import json,sys; print(json.load(open('$EVIDENCE_DIR/04-models.json'))['data'][0]['id'])")

kubectl run curl-tester2 --rm -i --restart=Never --image=curlimages/curl:latest -n default --quiet --command -- \
  curl -sS -X POST http://$SVC:8000/v1/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"The capital of France is\",\"max_tokens\":20,\"temperature\":0}" \
    -w "\nHTTP=%{http_code} TIME=%{time_total}s\n" \
  > "$EVIDENCE_DIR/05-completion.json"
cat "$EVIDENCE_DIR/05-completion.json"
```

Expected (round 6 actual):
```json
{
  "id": "cmpl-6d4ae9f4-e9e2-4a9a-b152-8696ccf37049",
  "choices": [{
    "text": " Paris. The capital of France is Paris. The capital of France is Paris. The capital of France",
    "index": 0,
    "finish_reason": "length"
  }],
  "model": "meta-llama/Llama-3.1-8B-Instruct",
  "usage": {"prompt_tokens": 5, "completion_tokens": 20, "total_tokens": 25},
  "nvext": {"timing": {"total_time_ms": 1882.46}}
}
HTTP=200  TIME=1.886s
```

Critical path the request walks:
1. Frontend (node `0be4f4fec`) receives POST.
2. Routes prefill to PrefillWorker (node `0be4f4fec` same host, but a separate pod).
3. PrefillWorker computes prompt KV cache, registers with NIXL.
4. DecodeWorker (node `0a3eb6d39` cross-node) pulls KV via NIXL LIBFABRIC over EFA RDMA.
5. DecodeWorker generates 20 tokens autoregressively.
6. Response returned.

If decode crashes with `NIXL_ERR_BACKEND` instead: the
`kv_connector_extra_config:{backends:["LIBFABRIC"]}` is missing — vLLM's NixlConnector
defaults to UCX which fails on EFA RDM endpoints. (This was the rev7 root cause.)

## 8. Cleanup

```bash
kubectl delete dgd dynamo-combined-vllm -n default --wait=true --timeout=60s
# Release lock
```

## 9. Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Frontend `0/0 instances` from KubeDiscoveryClient | Worker readinessProbe missing → EndpointSlice stays ready=False | Keep the readinessProbe on port 9090 path /health |
| Decode crashes on first request, `NIXL_ERR_BACKEND` | NixlConnector defaulted to UCX | Add `kv_connector_extra_config:{backends:["LIBFABRIC"]}` to `--kv-transfer-config` |
| HTTP 500 `invalid type: unit variant` | Decode crashed earlier; Dynamo 1.1.0 emits bare `finish_reason:"error"` (handlers.py bug) | Real cause is upstream of the 500; inspect decode logs |
| Frontend HF 401 on USE_POLICY.md | hf-token secret missing `HF_TOKEN` + `HUGGING_FACE_HUB_TOKEN` keys | `kubectl edit secret hf-token` to add both keys (just `token` is not enough) |
| PrefillWorker scheduled on P4d node, no RDMA verbs | nodeSelector missing | Already in YAML: `node.kubernetes.io/instance-type: ml.p5.48xlarge` |

## 10. Files in this directory

- `01-dgd-as-deployed.yaml` — manifest with image SHA substituted
- `02-apply.log` — kubectl apply output
- `03-pods.txt` — pod placement (cross-node confirmed)
- `04-models.json` — T11 response
- `05-completion.json` — T12 response (HTTP 200)
- `VERDICT.md` — analysis
- `REPRODUCE.md` — this document
