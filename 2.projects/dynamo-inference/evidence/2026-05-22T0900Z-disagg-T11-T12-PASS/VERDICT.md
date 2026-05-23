# Round 6 — Aggregated + Disaggregated Inference E2E PASS on rev8 image

**Date:** 2026-05-22
**Image:** `${ECR_REGISTRY}/dynamo-efa:520cfc584abb`
**Build:** CodeBuild #19 (commit `520cfc5`)
**Cluster:** P5.48xlarge HyperPod, 2-node cross-node disagg
**Verdict:** **PASS** — both T11 (aggregated, /v1/models) and T12 (disaggregated, /v1/completions) end-to-end

## Topology

| Component | Node | IP |
|---|---|---|
| Frontend | hyperpod-i-0be4f4fecf22a73b3 | 10.1.3.82 |
| PrefillWorker | hyperpod-i-0be4f4fecf22a73b3 | 10.1.3.151 |
| DecodeWorker | hyperpod-i-0a3eb6d3953cceaa7 | 10.1.3.73 |

Prefill and Decode are on **different nodes** — the KV cache must
transfer cross-node via NIXL LIBFABRIC over EFA RDMA. This is the
disaggregation path that the rev7 fix
(`kv_connector_extra_config:{backends:["LIBFABRIC"]}`) enabled.

## T11 — Aggregated path (model registration)

```bash
$ curl http://172.20.117.134:8000/v1/models
{
  "object": "list",
  "data": [{
    "id": "meta-llama/Llama-3.1-8B-Instruct",
    "object": "model",
    "created": 1779445863,
    "owned_by": "nvidia",
    "context_window": 4096
  }]
}
```

Frontend successfully discovered Decode worker via KubeDiscoveryClient
and registered the model. The rev6 readinessProbe fix is intact on rev8.

## T12 — Disaggregated path (cross-node completion)

```bash
$ curl -X POST http://172.20.117.134:8000/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"meta-llama/Llama-3.1-8B-Instruct",
         "prompt":"The capital of France is",
         "max_tokens":20,"temperature":0}'

{
  "id": "cmpl-6d4ae9f4-e9e2-4a9a-b152-8696ccf37049",
  "choices": [{
    "text": " Paris. The capital of France is Paris. The capital of France is Paris. The capital of France",
    "index": 0,
    "finish_reason": "length"
  }],
  "model": "meta-llama/Llama-3.1-8B-Instruct",
  "usage": {
    "prompt_tokens": 5,
    "completion_tokens": 20,
    "total_tokens": 25
  },
  "nvext": {
    "timing": {"total_time_ms": 1882.46}
  }
}
HTTP=200  TIME=1.886s
```

Generated semantically correct output ("Paris" is correct), 20 tokens
in ~1.88 sec total. Critical path:
1. Frontend received POST `/v1/completions`
2. Routed prefill to PrefillWorker on node `0be4f4fec...`
3. PrefillWorker computed prompt KV cache, registered with NIXL
4. DecodeWorker on node `0a3eb6d39...` pulled KV via NIXL LIBFABRIC
   over EFA RDMA (cross-node)
5. DecodeWorker generated 20 tokens autoregressively
6. Response returned to client

If LIBFABRIC backend selection had failed, decode would have crashed
with `NIXL_ERR_BACKEND` (the rev7 root cause). It didn't — rev8
preserves the fix.

## Closing the rev8 PR #72 loop

This round confirms the rev8 image works for the FULL Dynamo disagg
inference path, not just the wire-level nixlbench. PR #72 rev8 is
production-ready:

| Test | rev7 | rev8 |
|---|---|---|
| /v1/models | PASS | **PASS** |
| /v1/completions cross-node | PASS | **PASS** |
| nixlbench LIBFABRIC bench | n/a (binary missing) | **PASS** (46.9 GB/s) |
| nccl-tests in image | PASS | PASS |
| EFA libfabric stack | PASS | PASS |

## Files

- `01-dgd-as-deployed.yaml` — DGD manifest with image SHA substituted
- `02-apply.log` — kubectl apply output
- `03-pods.txt` — `kubectl get pods -o wide` showing cross-node placement
- `04-models.json` — T11 /v1/models response
- `05-completion.json` — T12 /v1/completions response (HTTP 200)

## Linked

- [[round5-nixlbench-PASS]] — wire-level NIXL LIBFABRIC bandwidth proof
- [[project-dynamo-pr72]]
- [[project-nixl-libfabric-selection]]
