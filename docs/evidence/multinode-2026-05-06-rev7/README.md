# rev7 — T12d PASS — end-to-end disaggregated /v1/completions

**Status: ALL GATES GREEN.** Disaggregated inference returns real tokens over
EFA RDMA + NIXL LIBFABRIC transport on the `dynamo-combined-efa` image.

## Summary of the rev6 → rev7 delta

One-line fix in `k8s/dgd-dynamo-combined-vllm.yaml`: extend
`--kv-transfer-config` JSON with `kv_connector_extra_config.backends`:

```yaml
# rev6 (broken — silently fell back to UCX which can't handshake cross-node):
--kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}'

# rev7 (forces LIBFABRIC, cross-node transfer works):
--kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both","kv_connector_extra_config":{"backends":["LIBFABRIC"]}}'
```

## Root cause (independent investigation, confirmed)

vLLM's `NixlConnector` has the default hardcoded at
`vllm/distributed/kv_transfer/kv_connector/v1/nixl_connector.py:1022-1024`:

```python
self.nixl_backends = vllm_config.kv_transfer_config.get_from_extra_config(
    "backends", ["UCX"]
)
```

No env-var read path. `NIXL_BACKEND`, `VLLM_NIXL_KVCACHE_BACKEND` (and every
other env we tried from rev2 onward) are silently ignored. The only way to
pick LIBFABRIC is via the JSON extra_config.

Upstream issue filed: `vllm-project/vllm#41814`.

## Gate matrix

| Gate | rev5 | rev6 | rev7 | Evidence |
| ---- | ---- | ---- | ---- | -------- |
| Pods Running & Ready | FAIL | PASS | **PASS** | `t12-pods.txt` |
| EndpointSlices `ready=true` | FAIL | PASS | **PASS** | `t12-endpointslices.yaml` |
| KubeDiscoveryClient instances > 0 | 0 | 6 | **6** | `t12-frontend-PASS.log` |
| `/v1/models` returns model | FAIL | PASS | **PASS** | same log |
| NIXL backend == LIBFABRIC | N/A | FAIL (UCX) | **PASS** | `t12-decode-PASS.log` — `Backend LIBFABRIC was instantiated` |
| `/v1/completions` non-stream | FAIL | FAIL | **PASS** | `t12d-nostream.json` |
| `/v1/completions` SSE stream | FAIL | FAIL | **PASS** | `t12d-stream.sse` |
| `/v1/chat/completions` | FAIL | FAIL | **PASS** | `t12d-chat.json` |

## Proof of work

`t12d-nostream.json` (HTTP 200, 745 ms):

```json
{"id":"cmpl-0807a0be-...","choices":[{"text":" Paris. The capital of France is Paris. The capital of France is Paris. The capital of France","index":0,"finish_reason":"length"}],"object":"text_completion","usage":{"prompt_tokens":5,"completion_tokens":20,"total_tokens":25}}
```

`t12d-chat.json` (HTTP 200, 71 ms):

```json
{"id":"chatcmpl-25a2658e-...","choices":[{"index":0,"message":{"content":"It's nice to meet you. Is there something","role":"assistant"}...}],"object":"chat.completion","usage":{"prompt_tokens":36,"completion_tokens":10,"total_tokens":46}}
```

Worker trace (`t12-decode-PASS.log`):

```
NIXL INFO _api.py:361 Backend LIBFABRIC was instantiated
handle_payload: request received  component=backend  endpoint=generate  ...
handle_payload: request completed (elapsed_ms=737)
```

## Environment

- Image: `058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-efa:9467d1460c71` (Dynamo 1.1.0 + vLLM 0.19.1)
- Operator: `nvcr.io/nvidia/ai-dynamo/kubernetes-operator:1.0.1`
- Model: `meta-llama/Llama-3.1-8B-Instruct`
- Transport: EFA RDMA via libfabric 2.4.0amzn3.0, NIXL 0.6.x with LIBFABRIC plugin
- Nodes: `hyperpod-i-0a3eb6d3953cceaa7` (Frontend + Decode on H100), `ip-10-1-0-198` (Prefill on H100)

## Known minor warning (non-fatal)

```
W libfabric_rail_manager.cpp:543] Could not deduce average EFA device upstream link bandwidth,
W libfabric_rail_manager.cpp:259] Using default (all) rail selection policy for DRAM memory type
```

NIXL falls back to all-rail selection. No measured impact on T12d at our message sizes. Will tune `NIXL_LIBFABRIC_MAX_RAILS` in a follow-up if p50 latency becomes a gate.

## Files

- `t12d-nostream.json` — HTTP 200 JSON completion
- `t12d-stream.sse` — HTTP 200 SSE completion tokens + `[DONE]`
- `t12d-chat.json` — HTTP 200 chat completion
- `t12-dgd-applied.yaml` — DGD spec as applied
- `t12-pods.txt` — pod Ready status
- `t12-endpointslices.yaml` — EndpointSlice ready=true on all 3
- `t12-decode-PASS.log` — Backend LIBFABRIC + all 3 request completions
- `t12-prefill-PASS.log` — prefill request trace
- `t12-frontend-PASS.log` — Frontend routing trace
