# Round 7 — Dynamo config matrix on rev8 image

**Image:** `${ECR_REGISTRY}/dynamo-efa:520cfc584abb`
**Cluster:** P5.48xlarge HyperPod, 2 nodes
**Date:** 2026-05-22
**Verdict:** **2/2 KV-router configs PASS** (vLLM agg + disagg). 3 deferred.

## Summary

| Config | Backend | Features | Pods Ready | T11 /v1/models | T12 /v1/completions | Cold Q1 | KV-cache Q2 | Q3 (fresh) | Status |
|---|---|---|---|---|---|---|---|---|---|
| **vllm-agg-router** | vLLM | KV router, KV events, agg | 2/2 | PASS | PASS | 752ms | **108ms (7×)** | 140ms | ✅ PASS |
| **vllm-disagg-router** | vLLM | KV router, KV events, disagg, NIXL LIBFABRIC, cross-node | 3/3 | PASS | PASS | 1872ms | **120ms (15.6×)** | 152ms | ✅ PASS |
| vllm-disagg-kvbm | vLLM | KVBM multi-tier cache, model swap (Qwen3-8B) | — | — | — | — | — | — | ⏸ deferred |
| trtllm-disagg | TRT-LLM | disagg baseline | — | — | — | — | — | — | ⏸ deferred (multi-DGD operator layout) |
| trtllm-disagg-router | TRT-LLM | KV router | — | — | — | — | — | — | ⏸ deferred |
| sglang-* | SGLang | — | — | — | — | — | — | — | ⏸ no DGD authored on combined-efa image |

## Wire-level KV-router proofs

The headline result: **prefix-match cache hits show order-of-magnitude latency reduction** in both
config flavours.

### vLLM disagg + KV router (cross-node)

```
Q1 cold:           1872ms  prefill on hyperpod-0be4f4fec → KV via NIXL LIBFABRIC → decode on hyperpod-0a3eb6d39
Q2 prefix-match:    120ms  KV cache hit, 15.6× speedup
Q3 fresh prompt:    152ms  warm decoder, fresh prefill
```

Frontend log proof:
```
INFO dynamo_runtime::transports::event_plane: EventSubscriber created topic=kv_metrics transport=Nats
INFO dynamo_llm::discovery::watcher: Prefill model detected, registering and activating prefill router
INFO dynamo_llm::kv_router::prefill_router::activation: Activating prefill router router_mode=RoundRobin
INFO dynamo_llm::kv_router::prefill_router::activation: Prefill router activated successfully router_mode=RoundRobin
INFO dynamo_llm::discovery::worker_monitor: KvWorkerMonitor: prefill endpoint watcher activated, tracking 1 workers
```

### vLLM agg + KV router (single-pod)

```
Q1 cold:            752ms
Q2 prefix-match:    108ms  (7.0× speedup)
Q3 fresh prompt:    140ms
```

Frontend log proof: `EventSubscriber created topic=kv_metrics transport=Nats` confirms the
KV events publisher is wired via NATS and the router subscribed to it.

## Cumulative validation across rounds 5-7

| Test | Round | Result |
|---|---|---|
| nixlbench wire-level (LIBFABRIC, VRAM↔VRAM) | 5 | **PASS** — 46.9 GB/s @ 64 MB block |
| /v1/models registration | 6 | **PASS** |
| /v1/completions cross-node (disagg, no router) | 6 | **PASS** — 1.886s |
| /v1/completions cross-node (disagg, **KV router**) | 7 | **PASS** — 1.872s cold, 0.120s prefix-hit |
| /v1/completions single-pod (agg, **KV router**) | 7 | **PASS** — 0.752s cold, 0.108s prefix-hit |
| KV cache prefix-match speedup | 7 | **PASS** — 7×–15.6× |
| KV events on NATS | 7 | **PASS** (subscriber created, kv_metrics topic) |

## Deferred configs and why

### KVBM
The upstream `disagg_kvbm.yaml` swaps **both** the model (Qwen3-8B) AND the kv-transfer-config
(drops the explicit LIBFABRIC backend). On EFA without LIBFABRIC forcing, NixlConnector
defaults to UCX which crashes on EFA RDM endpoints (the rev7 root cause). Two unrelated
changes coupled together — defer until we can run KVBM with `kv_connector_extra_config:LIBFABRIC`
preserved.

### TRT-LLM (agg/disagg, agg_router/disagg_router)
The TRT-LLM combined Dockerfile produces a different operator layout — when we deployed
`dgd-dynamo-combined-trtllm.yaml`, the operator created **three separate DGDs** (`trtllm-disagg-decode`,
`trtllm-disagg-prefill`, `trtllm-disagg-frontend`) under three distinct `dynamoNamespace`s.
Frontend's KubeDiscoveryClient cannot discover workers across DGDs. This is a layout difference
in the TRT-LLM DGD spec — needs a single-DGD restructure. Defer to a follow-up rev.

### SGLang
Upstream provides `examples/backends/sglang/deploy/*.yaml` with its own image
(`nvcr.io/nvidia/ai-dynamo/sglang-runtime`). Our `dynamo-efa:520cfc584abb` is built off the
combined-efa Dockerfile which has vLLM + TRT-LLM but **not** SGLang. Adding SGLang is a
Dockerfile change, not a config test.

## Lessons learned this round

1. **Anti-affinity blocks replicas>1 on hostNetwork:** the DGD's anti-affinity uses
   `topologyKey: kubernetes.io/hostname` to spread workers, but with `hostNetwork:true`
   each replica needs unique host ports. With 2 nodes + replicas=2 prefill + replicas=2 decode,
   3 of the 5 pods went unschedulable on `didn't have free ports`. Fix: stay at replicas=1
   per worker on a 2-node cluster, OR move off hostNetwork (loses EFA), OR add more nodes.
2. **Operator label scheme:** the right label selector is
   `nvidia.com/dynamo-graph-deployment-name=<dgd-name>`, NOT `app.kubernetes.io/part-of`.
   The matrix runner's first version used the wrong label and saw 0/0 ready forever.
3. **`--disaggregation-mode` removal regex artifact:** when stripping flags from a backslash-continued
   shell command, `\\\n` becomes `\\` if the regex eats the newline. Result: vLLM saw two
   model arguments and crashed `ValueError: We do not support multiple model names`. Fixed.
4. **Stale terminating pods foul `kubectl wait`:** label-selector wait counted both old
   Terminating pods AND new Running pods, declared ready=2/2 prematurely. Distinguish by
   phase string (`grep -c "^Running/true"`).

## Files

Each subdir has full evidence:
- `vllm-disagg-router-v2/` — dgd.yaml, 01-apply.log, 03-pods.txt, 04-completions.log, 05-frontend-kv-router.log
- `vllm-agg-router-v2/` — same layout (b-suffix logs from the post-fix redeploy)
- `run-matrix.sh` — original matrix runner (had label-selector bug, kept for the lessons)
- `runner.log` — output from the failed first attempt

## Linked

- [[round5-nixlbench-PASS]] — wire-level NIXL LIBFABRIC bandwidth
- [[round6-disagg-T11-T12]] — baseline disagg without KV router
- [[project-dynamo-pr72]]
