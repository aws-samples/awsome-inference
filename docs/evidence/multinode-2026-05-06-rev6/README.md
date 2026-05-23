# rev6 — T12 ReadinessProbe Fix Validation

## Summary

**T12a/b/c (discovery chain): PASS** — the readinessProbe fix on worker pods
resolves the `KubeDiscoveryClient::list returning 0 instances` bug reported
in rev5. All three Dynamo services (Frontend, PrefillWorker, DecodeWorker)
reach `Running+Ready`, their EndpointSlices carry `ready=true`, and Frontend
returns the model in `/v1/models`.

**T12d (end-to-end /v1/completions): NO-GO** — gated on a **separate**
downstream bug: NIXL backend selection falls back to UCX even when
`NIXL_BACKEND=LIBFABRIC` is set. Cross-node UCX handshake fails with
`handshake_failed`. Not caused by the namespace / readiness issue this
revision was meant to close out.

## What changed vs rev5

- `k8s/dgd-dynamo-combined-vllm.yaml` — added an explicit `readinessProbe`
  on `PrefillWorker` and `DecodeWorker` (httpGet `/health` on
  `DYN_SYSTEM_PORT=9090`, initialDelay 120 s, failureThreshold 60).
- Rationale documented in `docs/DEEPEP-HANDOFF-2026-04-22.md` and the new
  skill `~/.claude/skills/dynamo-kube-discovery-readiness/SKILL.md`.
- Upstream PR filed to fix the misleading comment in
  `component_worker.go`: ai-dynamo/dynamo#9201.

## Gate matrix

| Gate | Status | Evidence |
| ---- | ------ | -------- |
| T1–T11 | PASS (same as rev5) | See rev5 evidence bundle |
| T12a: pods Ready | **PASS** | `t12-pods.txt` shows 3/3 Running 1/1 Ready |
| T12b: EndpointSlices ready=true | **PASS** | `t12-endpointslices.yaml` |
| T12c: `/v1/models` returns model | **PASS** | Frontend `KubeDiscoveryClient::list returning 6 instances`; curl shows `{"id":"meta-llama/Llama-3.1-8B-Instruct"...}` |
| T12d: `/v1/completions` returns text | **NO-GO** | `t12-decode.log` shows `NIXL transfer failure: handshake_failed` — UCX backend instantiated instead of LIBFABRIC |

## Root-cause chain confirmed

rev5 hypothesis (EndpointSlice `ready=False` blocks Frontend discovery)
is now **proven** by the fix passing T12a–c:

```
rev5 (no probe)          rev6 (httpGet /health probe)
─────────────────        ─────────────────────────────
Pod.Ready = False        Pod.Ready = True
EndpointSlice.ready=F    EndpointSlice.ready=T
Frontend.instances = 0   Frontend.instances = 6
/v1/models → []          /v1/models → [{"id":"...3.1-8B..."}]
```

## Remaining T12d blocker (separate from this revision)

NIXL `add_remote_agent` fails with `handshake_failed` across nodes.
Decode log excerpt:

```
Backend UCX was instantiated
...
NIXL transfer failure: handshake_failed
  request_id: 1c25e542-9420-...
  remote_host: 10.1.0.198
  remote_port: 5700
```

Despite setting:

- `NIXL_BACKEND=LIBFABRIC`
- `VLLM_NIXL_KVCACHE_BACKEND=LIBFABRIC`
- `FI_PROVIDER=efa`, `FI_EFA_USE_DEVICE_RDMA=1`

the NIXL Python `_api.py` selects UCX. Both `libplugin_LIBFABRIC.so` and
`libplugin_UCX.so` are present in `/opt/nvidia/nvda_nixl/lib64/plugins/`,
so the plugin is available but not chosen. This is the next layer to
debug — does not affect the T12 KubeDiscoveryClient closure.

## Environment

- Image: `058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-efa:9467d1460c71`
  (Dynamo 1.1.0)
- Operator: `nvcr.io/nvidia/ai-dynamo/kubernetes-operator:1.0.1`
- Model: `meta-llama/Llama-3.1-8B-Instruct`
- Nodes: `hyperpod-i-0a3eb6d3953cceaa7` (frontend + prefill),
  `ip-10-1-0-198` (decode). `hyperpod-i-01aee349f9991c414` cordoned
  due to unrelated containerd pause-image issue.

## Files

- `t12-dgd-applied.yaml` — live DGD spec
- `t12-pods.txt` — pod status (all Ready)
- `t12-endpointslices.yaml` — EndpointSlice readiness (all ready=true)
- `t12-dwm.yaml` — DynamoWorkerMetadata CRs (present, names match pods)
- `t12-frontend.log` — Frontend discovery trace
- `t12-prefill.log` — PrefillWorker model load + endpoint register
- `t12-decode.log` — DecodeWorker NIXL handshake failure
