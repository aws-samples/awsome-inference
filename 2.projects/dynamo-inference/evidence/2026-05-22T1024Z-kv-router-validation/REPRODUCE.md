# Round 7 — Reproduce: KV-router configs on rev8 image

**Goal:** Reproduce two passing KV-router tests on rev8 image:
- vLLM aggregated + KV router (single pod) — 7.0× prefix-cache speedup
- vLLM disaggregated + KV router (cross-node) — 15.6× prefix-cache speedup

This doc also documents the 3 deferred configs and exactly why they're deferred.

## 1. Environment

| Item | Value |
|---|---|
| Date of run | 2026-05-22 ~10:40–15:25 UTC |
| Cluster | EKS HyperPod, p5.48xlarge × 2 |
| Image SHA | `dynamo-efa:520cfc584abb` |
| Model | `meta-llama/Llama-3.1-8B-Instruct` |
| Frontend node (disagg) | hyperpod-i-0be4f4fec |
| PrefillWorker node (disagg) | hyperpod-i-0be4f4fec |
| DecodeWorker node (disagg) | hyperpod-i-0a3eb6d39 (cross-node) |
| Frontend node (agg) | hyperpod-i-0a3eb6d39 |
| VllmWorker node (agg) | hyperpod-i-0be4f4fec |

## 2. Prerequisites

Same as round 6 (image, ETCD/NATS, hf-token secret, FSx PVC, lock).

Plus: NATS server reachable for KV-events transport. The rev6 manifest already wires NATS;
no extra config needed.

## 3. Author the patched manifests

Both configs derive from the rev6 base (`dgd-dynamo-combined-vllm.yaml`).

### 3.1 vllm-disagg-router (4 deltas vs rev6 base)

```python
# /tmp/awsome-inference-1/2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml
# → docs/evidence/rev8-pr72-e2e-2026-05-21/round7-config-matrix/vllm-disagg-router-v2/dgd.yaml
import re
src = '/tmp/awsome-inference-1/2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml'
text = open(src).read()

# 1. Bump image SHA: rev6 → rev8
text = text.replace('dynamo-efa:9467d1460c71', 'dynamo-efa:520cfc584abb')

# 2. Inject DYN_ROUTER_MODE=kv into PrefillWorker + DecodeWorker envs
inject_env = '        - { name: DYN_ROUTER_MODE,           value: "kv" }\n'
text = text.replace(
    '        - { name: DYNAMO_BACKEND,             value: "vllm" }\n        - { name: ETCD_ENDPOINTS',
    '        - { name: DYNAMO_BACKEND,             value: "vllm" }\n' + inject_env + '        - { name: ETCD_ENDPOINTS')

# 3. Inject --kv-events-config flag into both worker dynamo.vllm exec
inject_kvevents = "                --kv-events-config '{\"publisher\":\"zmq\",\"topic\":\"kv-events\",\"endpoint\":\"tcp://*:20080\",\"enable_kv_cache_events\":true}' \\\n"
text = text.replace(
    '                --gpu-memory-utilization 0.85',
    inject_kvevents + '                --gpu-memory-utilization 0.85')

# 4. Replicas: bumping to 2 was the upstream pattern, but on a 2-node cluster with
#    hostNetwork:true, replicas=2 prefill + replicas=2 decode causes port collisions
#    (DYN_SYSTEM_PORT=9090, VLLM_NIXL_SIDE_CHANNEL_PORT=5700). Stay at replicas=1.
#    KV router activates regardless of replica count.

open('vllm-disagg-router-v2/dgd.yaml', 'w').write(text)
```

### 3.2 vllm-agg-router (single-pod, no separate prefill)

Build on top of disagg-router by stripping `--disaggregation-mode` flags and dropping
the PrefillWorker block:

```python
# WARNING: regex-based --disaggregation-mode strip leaves a `\\ \\` artifact that breaks
# vLLM arg parsing (`We do not support multiple model names`). Apply this fix afterward:
#   sed -i 's|--served-model-name meta-llama/Llama-3.1-8B-Instruct \\\\ \\\\|--served-model-name meta-llama/Llama-3.1-8B-Instruct \\|g' dgd.yaml

text = open('vllm-disagg-router-v2/dgd.yaml').read()
# Drop --disaggregation-mode flags (both prefill and decode workers had it)
text = re.sub(r"\s*--disaggregation-mode (prefill|decode) \\\n", " \\\n", text)
# Drop PrefillWorker block (from `    PrefillWorker:` to start of `    DecodeWorker:`)
m = re.search(r"    PrefillWorker:\n.*?(?=    DecodeWorker:)", text, re.DOTALL)
text = text.replace(m.group(0), "")
# Rename DecodeWorker → VllmWorker (semantic, agg has no role split)
text = text.replace(
    "    DecodeWorker:\n      envFromSecret: hf-token\n      componentType: worker\n      subComponentType: decode\n",
    "    VllmWorker:\n      envFromSecret: hf-token\n      componentType: worker\n")
open('vllm-agg-router-v2/dgd.yaml', 'w').write(text)
```

## 4. Test sequence (run for both configs in turn)

```bash
EVIDENCE_DIR=docs/evidence/rev8-pr72-e2e-2026-05-21/round7-config-matrix/vllm-disagg-router-v2

# Apply
kubectl apply -f "$EVIDENCE_DIR/dgd.yaml" 2>&1 | tee "$EVIDENCE_DIR/01-apply.log"

# Wait for fresh pods Running/true (use grep -c "^Running/true" to filter Terminating)
for i in $(seq 1 60); do
  ALL=$(kubectl get pods -n default \
    -l "nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm" \
    -o jsonpath='{range .items[*]}{.status.phase}/{.status.containerStatuses[0].ready};{end}')
  RDY=$(echo "$ALL" | tr ';' '\n' | grep -c "^Running/true")
  TERM=$(echo "$ALL" | tr ';' '\n' | grep -c "Terminating\|Pending\|CrashLoopBackOff\|Error")
  echo "$(date -u +%H:%M:%SZ) ready=$RDY issues=$TERM"
  if [ "$RDY" -ge 3 ] && [ "$TERM" = "0" ]; then break; fi  # disagg: 3 pods (frontend+prefill+decode)
  if [ "$RDY" -ge 2 ] && [ "$TERM" = "0" ]; then break; fi  # agg: 2 pods (frontend+vllmworker)
  sleep 15
done

kubectl get pods -n default -l nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm -o wide \
  > "$EVIDENCE_DIR/03-pods.txt"

SVC=$(kubectl get svc -n default dynamo-combined-vllm-frontend -o jsonpath='{.spec.clusterIP}')

# T11 — /v1/models
kubectl run kvr-t1 --rm -i --restart=Never --image=curlimages/curl:latest -n default --quiet --command -- \
  curl -sS http://$SVC:8000/v1/models > "$EVIDENCE_DIR/04-models.json"

# Q1 — cold completion
kubectl run kvr-t2 --rm -i --restart=Never --image=curlimages/curl:latest -n default --quiet --command -- \
  curl -sS -X POST http://$SVC:8000/v1/completions -H "Content-Type: application/json" \
    -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"The capital of France is","max_tokens":20,"temperature":0}' \
    -w "\nHTTP=%{http_code} TIME=%{time_total}s\n"

# Q2 — same prefix (KV cache hit)
kubectl run kvr-t3 --rm -i --restart=Never --image=curlimages/curl:latest -n default --quiet --command -- \
  curl -sS -X POST http://$SVC:8000/v1/completions -H "Content-Type: application/json" \
    -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"The capital of France is","max_tokens":15,"temperature":0}' \
    -w "\nHTTP=%{http_code} TIME=%{time_total}s\n"

# Q3 — fresh prompt
kubectl run kvr-t4 --rm -i --restart=Never --image=curlimages/curl:latest -n default --quiet --command -- \
  curl -sS -X POST http://$SVC:8000/v1/completions -H "Content-Type: application/json" \
    -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"In quantum mechanics, the","max_tokens":20,"temperature":0}' \
    -w "\nHTTP=%{http_code} TIME=%{time_total}s\n"

# Pull KV-router proof from Frontend logs
kubectl logs -n default -l "nvidia.com/dynamo-component=Frontend,nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm" --tail=200 \
  | grep -iE "kv|router|prefix|prefill" | tail -15 > "$EVIDENCE_DIR/05-frontend-kv-router.log"
```

## 5. Expected outputs

### vLLM disagg + KV router (round 7 actual)

```
Q1 cold:           HTTP=200  TIME=1.872s   "Paris..."
Q2 prefix-match:   HTTP=200  TIME=0.120s   "Paris..."   (15.6× speedup)
Q3 fresh:          HTTP=200  TIME=0.152s   "wave function..."
```

Frontend log proof:
```
INFO dynamo_runtime::transports::event_plane: EventSubscriber created topic=kv_metrics transport=Nats
INFO dynamo_runtime::discovery::kube: KubeDiscoveryClient::list_and_watch started for query=Endpoint { namespace: "default-dynamo-combined-vllm-<hash>", component: "prefill", endpoint: "generate" }
INFO dynamo_llm::discovery::watcher: Prefill model detected, registering and activating prefill router model_name="meta-llama/Llama-3.1-8B-Instruct"
INFO dynamo_llm::kv_router::prefill_router::activation: Activating prefill router router_mode=RoundRobin
INFO dynamo_llm::kv_router::prefill_router::activation: Prefill router activated successfully router_mode=RoundRobin
INFO dynamo_llm::discovery::worker_monitor: KvWorkerMonitor: prefill endpoint watcher activated, tracking 1 workers
```

### vLLM agg + KV router (round 7 actual)

```
Q1 cold:           HTTP=200  TIME=0.752s
Q2 prefix-match:   HTTP=200  TIME=0.108s   (7.0× speedup)
Q3 fresh:          HTTP=200  TIME=0.140s
```

Frontend log proof: `EventSubscriber created topic=kv_metrics transport=Nats`

## 6. Teardown between configs

```bash
kubectl delete dgd dynamo-combined-vllm -n default --wait=true --timeout=60s
# Wait for pods to drain
for i in $(seq 1 30); do
  N=$(kubectl get pods -n default -l "nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm" 2>/dev/null | tail -n +2 | wc -l)
  [ "$N" = "0" ] && break
  sleep 5
done
```

## 7. Why each deferred config is deferred

### KVBM (vllm-disagg-kvbm)
Upstream `examples/backends/vllm/deploy/disagg_kvbm.yaml` couples 3 changes:
1. Model swap: `Qwen/Qwen3-0.6B` → `Qwen/Qwen3-8B`
2. Drops the `kv_connector_extra_config.backends` (LIBFABRIC forcing) — uses default UCX
3. Adds `--enforce-eager`, `DYN_KVBM_CPU_CACHE_GB=100`, `--max-model-len=32000`

Change #2 is unsafe on EFA: NixlConnector defaults to UCX which fails on EFA RDM endpoints
(rev7 root cause). KVBM with LIBFABRIC retained is reproducible — author a manifest that
keeps `kv_connector_extra_config:{backends:["LIBFABRIC"]}` in the kv-transfer-config and
adds the rest of the KVBM deltas.

### TRT-LLM (any variant)
The combined-efa Dockerfile produces a single image with both vLLM and TRT-LLM stages.
The DGD `dgd-dynamo-combined-trtllm.yaml` declares its three services (Frontend, Decode,
Prefill) but the Dynamo Operator stamps **separate `dynamoNamespace` per service** — when
deployed, three independent DGDs appear (`trtllm-disagg-frontend`, `-decode`, `-prefill`)
each in its own namespace. Frontend's KubeDiscoveryClient cannot discover workers across
namespaces. Restructure required: one DGD with all three services under the same
namespace, matching the vLLM DGD layout.

### SGLang
Upstream provides `examples/backends/sglang/deploy/*.yaml` using
`nvcr.io/nvidia/ai-dynamo/sglang-runtime`. Our `dynamo-efa:520cfc584abb` was built from
`Dockerfile.dynamo-combined-efa` which has vLLM + TRT-LLM stages but no SGLang stage.
Adding SGLang requires Dockerfile changes (a new sglang-stage and a `combined-sglang`
multi-tier merge), not just a config test.

## 8. Lessons (capture in skill files)

1. Operator label is `nvidia.com/dynamo-graph-deployment-name=<dgd-name>`,
   not `app.kubernetes.io/part-of`.
2. `hostNetwork:true` + `replicas>1` collides on `DYN_SYSTEM_PORT=9090` and
   `VLLM_NIXL_SIDE_CHANNEL_PORT=5700`. Either drop hostNetwork (loses EFA) or stay at
   replicas=1.
3. Anti-affinity is by `kubernetes.io/hostname` — with 2 nodes and 5 pods (1 Frontend +
   2 Prefill + 2 Decode), 3 pods go unschedulable.
4. Stale terminating pods foul the readiness wait — distinguish by phase:
   `grep -c "^Running/true"` not just `grep -c "true"`.
5. Regex-stripping `--disaggregation-mode` from a backslash-continued shell command
   leaves `\\ \\` which vLLM parses as a 2nd model arg → `We do not support multiple
   model names`. Always re-validate the YAML after regex edits.

## 9. Files

- `vllm-disagg-router-v2/dgd.yaml` — patched DGD (rev6 base + 4 deltas)
- `vllm-disagg-router-v2/03-pods.txt` — cross-node placement
- `vllm-disagg-router-v2/04-completions.log` — Q1+Q2+Q3 outputs with HTTP+timing
- `vllm-disagg-router-v2/05-frontend-kv-router.log` — kv_router activation logs
- `vllm-agg-router-v2/dgd.yaml` — patched DGD (disagg-router base + agg deltas)
- `vllm-agg-router-v2/03-pods.txt`, `04-completions.log`, `05-frontend-kv-router.log`
- `run-matrix.sh` — original automated runner (had label-selector bug; kept for reference)
- `runner.log` — failed first-attempt output
- `VERDICT.md` — analysis + cumulative table
- `REPRODUCE.md` — this document
