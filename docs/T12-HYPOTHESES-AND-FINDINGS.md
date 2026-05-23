# T12 — Hypotheses and findings log (rev3 → rev7)

This document captures the chain of hypotheses, false leads, validated findings,
and upstream issues opened while debugging T12 (`/v1/completions` end-to-end on
disaggregated vLLM + EFA RDMA + NIXL). It exists so future revs don't re-walk
the same dead ends.

## Timeline

| Rev | Date (UTC) | Outcome | Primary hypothesis under test |
| --- | ---------- | ------- | ----------------------------- |
| rev3 | 2026-05-05 | NO-GO | Namespace mismatch between 3 separate DGDs |
| rev4 | 2026-05-06 | NO-GO | Namespace mismatch, operator hash suffix |
| rev5 | 2026-05-06 | NO-GO (3 of 4 gates) | Dynamo 1.1.0 bump + discovery timing |
| rev6 | 2026-05-06 | Partial PASS (T12a/b/c) | Missing worker `readinessProbe` blocks EndpointSlice |
| rev7 | 2026-05-06 | **FULL PASS** | vLLM NIXL backend default is hardcoded UCX |

## The hypothesis chain

### H1 — Three DGDs create per-service namespace mismatch (rev3)

**Hypothesis**: The operator stamps each service with
`<k8s-ns>-<dgd-name>-<service>` as the Dynamo namespace. Three separate DGDs
→ three different namespaces → Frontend can't see workers.

**Evidence**: `kubectl get dgd -o yaml` shows the operator warning
"`spec.services[X].dynamoNamespace is deprecated and ignored`" on all three.
Frontend log: `KubeDiscoveryClient::list returning 0 instances`.

**Outcome**: Merge to single DGD. Partial — see H2.

**Artifact**: skill `dgd-operator-namespace-suffix`.

### H2 — Single DGD still adds a per-worker hash suffix (rev4)

**Hypothesis**: Even with one DGD, the operator adds a content-based hash
suffix to worker namespaces (but not Frontend), so Frontend can't reach
workers.

**Evidence**: Worker namespaces observed as
`default-dynamo-combined-vllm-ae74a2d2` vs Frontend's
`default-dynamo-combined-vllm`.

**Fix**: `DYN_NAMESPACE=default-dynamo-combined-vllm` +
`DYN_NAMESPACE_WORKER_SUFFIX=""` on all services.

**Outcome**: Namespaces align. Still `0 instances`. H2 was necessary but not
sufficient.

### H3 — Dynamo 1.0.1 has a `KubeDiscoveryClient` bug fixed in 1.1.0 (rev5)

**Hypothesis**: Upstream issue 9200 implies 1.1.0 fixes the namespace/discovery
filter. Bump image to 1.1.0 and retry.

**Evidence**: Source inspection of `lib/runtime/src/discovery/kube/daemon.rs`
shows identical predicate at line 246 in both 1.0.1 and 1.1.0.

**Outcome**: Same symptom, same `0 instances`. Bump didn't help — the bug
isn't in the namespace/CR matching logic.

### H4 — `ready=False` on worker EndpointSlices blocks discovery (rev5 → rev6)

**Hypothesis**: The `daemon.rs:246` predicate filters on
`endpoint.conditions.ready == true`. Without a `readinessProbe`, kubelet keeps
Pod Ready=False during model load, which keeps the EndpointSlice not-ready,
which filters out the worker silently.

**Evidence**:
```
$ kubectl get endpointslice -o jsonpath='{.items[*].endpoints[*].conditions.ready}'
false false false  ← all workers
```
Source: `lib/runtime/src/discovery/kube/utils.rs:22-51` and
`daemon.rs:246`.

**Fix**: Add explicit `readinessProbe` (`httpGet /health`,
`failureThreshold: 60`, `initialDelaySeconds: 120`) to each worker's
`mainContainer`. Match the operator's injected port (`system`, 9090) and
handler type to avoid "may not specify more than 1 handler type" k8s rejection.

**Outcome**: **T12a/b/c PASS.** Frontend reports `KubeDiscoveryClient::list
returning 6 instances`. `/v1/models` returns the registered model.

**Artifact**: skill `dynamo-kube-discovery-readiness`. Upstream docs PR
`ai-dynamo/dynamo#9201` to fix the misleading `component_worker.go` comment.

### H5 — NIXL falls back to UCX despite `NIXL_BACKEND=LIBFABRIC` (rev6 → rev7)

**Hypothesis (initial, WRONG)**: Setting `NIXL_BACKEND=LIBFABRIC` and
`VLLM_NIXL_KVCACHE_BACKEND=LIBFABRIC` env vars should select the libfabric
backend plugin.

**What we observed**: Decode log prints `Backend UCX was instantiated` and
subsequent `handshake_failed` on `add_remote_agent()` with EFA cross-node
transfers. vLLM warning: `Unknown vLLM environment variable detected:
VLLM_NIXL_KVCACHE_BACKEND`.

**Actual root cause (validated via source read)**:
`vllm/distributed/kv_transfer/kv_connector/v1/nixl_connector.py:1022-1024`:
```python
self.nixl_backends = vllm_config.kv_transfer_config.get_from_extra_config(
    "backends", ["UCX"]
)
```
There is no env var read path. `NIXL_BACKEND`, `VLLM_NIXL_KVCACHE_BACKEND`,
and every other env we had set since rev2 were silent no-ops. The only way
to select LIBFABRIC is via the `kv_connector_extra_config.backends` field
inside the `--kv-transfer-config` JSON.

**Fix**:
```yaml
args:
  - --kv-transfer-config
  - '{"kv_connector":"NixlConnector","kv_role":"kv_both","kv_connector_extra_config":{"backends":["LIBFABRIC"]}}'
```

**Outcome**: Decode log: `Backend LIBFABRIC was instantiated`. No more
`handshake_failed`. NIXL exchanges libfabric-native EP names.

**Upstream issues filed**:
- `vllm-project/vllm#41814` — "NixlConnector hardcodes backends=\"UCX\" default; no env-var override path"
- Cross-references `aws-samples/awsome-inference#72` and the earlier
  `ai-dynamo/dynamo#9200`.

### H6 — `fold completions stream: invalid type: unit variant, expected newtype variant` (rev7 intermediate, WRONG interpretation)

**Hypothesis (initial)**: Operator 1.0.1 vs runtime 1.1.0 version skew, or
prefill is returning a full-response shape when it should return KV handles
only.

**What we observed**:
```
Failed deserializing JSON to response
  err: invalid type: unit variant, expected newtype variant at line 1 column 55
  json_str: {"data":{"data":{"token_ids":[],"finish_reason":"error",...}}}
```
The Frontend routed the request to `component=prefill` (not `backend`/decode),
and the worker returned a double-wrapped JSON with `finish_reason:"error"`
and zero tokens. The Rust deserializer on the Frontend choked at column 55
on the `"error"` string.

**Actual root cause**: Client-side. `curl` without an explicit `stream` flag
defaults to a Dynamo code path that folds the streaming frames into a single
completion. When the upstream shape doesn't match the `ChoiceFinishReason`
Rust enum (which expects `{"error":<msg>}` newtype, not bare string
`"error"`), the fold fails. Explicit `stream:true` or `stream:false` takes
a different code path that parses correctly.

**Proof**:
- `curl -d '...,"stream":false'` → HTTP 200 with real tokens.
- `curl -d '...,"stream":true'` → HTTP 200 SSE tokens + `[DONE]`.
- `/v1/chat/completions` → HTTP 200 with real assistant message.
- All three hit `component=backend` (decode worker), not `component=prefill`
  as the failing case did. So the request *was* being routed correctly once
  the client sent a well-formed body.

**Side note**: rev7 prefill *did* also receive and complete its request
(request_id `4e808b0b-...`) in 357 ms — the KV handles were produced
correctly. The fold error was purely in how the Frontend consumed what
*both* workers returned. The `{"data":{"data":...}}` envelope is the normal
Dynamo push-handler wrapper; it was only misinterpreted because the
implicit-stream fold path expects it with specific enum shapes.

**No code fix required for our rev7 PASS.** Client should send explicit
`stream:false` or `stream:true`.

**Caveat (from second independent researcher pass)**: the underlying bug in
Dynamo's worker Python code is real and still present. On the sad path where
vLLM's `RequestOutput.outputs` is empty, `components/src/dynamo/vllm/handlers.py:2014`
emits `"finish_reason":"error"` (bare string). The Rust `FinishReason` enum at
`lib/llm/src/protocols/common.rs:44-56` is:

```rust
#[serde(rename = "error")]
Error(String),   // newtype — expects {"error":"<msg>"} or "error: <msg>"
```

So `"error"` bare triggers the `invalid type: unit variant, expected newtype
variant` deserialize error. A sister emission at `handlers.py:1705-1710` uses
the correct form: `"finish_reason": "error: No outputs from vLLM engine"`.

Our rev7 request stream never hits this path because it succeeds. But if a
future dispatch returns empty outputs (e.g., NIXL hiccup, engine abort), the
Frontend will again HTTP 500 instead of surfacing a real error. Track as
Dynamo follow-up:

- Patch `handlers.py:2014` to emit `"error: <reason>"` instead of bare
  `"error"`.
- Or harden the Rust enum to accept `BareError` via `#[serde(untagged)]`.

Filed as follow-up. Not required for T12 closure.

## Knobs and settings that turned out to be no-ops

These were set at various points between rev2 and rev7. Removing any of them
would not change the rev7 PASS outcome. Kept in the YAML for defensiveness
or because other subsystems read them:

| Env / arg | Effect | Keep? |
| --- | --- | --- |
| `NIXL_BACKEND=LIBFABRIC` | No read path in vLLM or NIXL Python API | Remove (was the whole trap) |
| `VLLM_NIXL_KVCACHE_BACKEND=LIBFABRIC` | Not a recognized vLLM env (warning emitted) | Remove |
| `NIXL_SKIP_TOPOLOGY_CHECK=1` | Reads in NIXL topology module — kept as defensive | Keep |
| `NIXL_LIBFABRIC_MAX_RAILS=1` | Read by libfabric plugin at runtime — active | Keep |
| `FI_PROVIDER=efa`, `FI_EFA_USE_DEVICE_RDMA=1` | Read by libfabric at provider init — active | Keep |
| `FI_EFA_ENABLE_SHM=0`, `FI_EFA_ENABLE_SHM_TRANSFER=0` | Read by libfabric provider — active | Keep |
| `DYN_NAMESPACE=...` | Dynamo 1.1.0 honors this for namespace override — active | Keep (already load-bearing) |
| `DYN_NAMESPACE_WORKER_SUFFIX=""` | Dynamo 1.1.0 honors — strips the hash suffix | Keep |
| `DYN_SYSTEM_PORT=9090` | Operator default; probe port alignment | Keep |
| `NIXL_PLUGIN_DIR=/opt/dynamo/.../plugins` | NIXL reads this to locate `libplugin_LIBFABRIC.so` | Keep (load-bearing) |

## What the rev6 readinessProbe + rev7 extra_config together unlock

The full dependency chain that had to land:

1. **Worker pod has `readinessProbe`** — otherwise EndpointSlice `ready=false`
2. **EndpointSlice `ready=true`** — otherwise `daemon.rs:246` filters
3. **KubeDiscoveryClient returns > 0 instances** — otherwise `/v1/models` is empty
4. **`/v1/models` registers the model** — otherwise Frontend routes 404
5. **NIXL instantiates LIBFABRIC (not UCX)** — otherwise cross-node handshake fails
6. **NIXL handshake succeeds** — otherwise KV transfer never starts
7. **Client sends explicit `stream:true/false`** — otherwise the implicit-fold path blows up on enum deserialization

All seven gates now pass. T12 is closed.

## Skills authored from this work

- `dgd-operator-namespace-suffix` — Layer 1-2 (namespace merge + DYN_NAMESPACE override)
- `dynamo-kube-discovery-readiness` — Layer 3 (the readinessProbe fix that was the real gate)
- `codebuild-dockerhub-429-recovery` — CodeBuild retry + public-ECR mirror pattern
- New skill forthcoming: `nixl-libfabric-backend-selection` — document the `extra_config.backends` route and the no-op envs

## Upstream issues / PRs opened

- `ai-dynamo/dynamo#9200` — KubeDiscoveryClient diagnostic gap
- `ai-dynamo/dynamo#9201` — docs PR: clarify `component_worker.go` ReadinessProbe comment
- `vllm-project/vllm#41814` — NixlConnector hardcoded UCX default + suggested env var + docs

## What to do if T12 regresses

1. Check `kubectl get endpointslice -o jsonpath='{.items[*].endpoints[*].conditions.ready}'` — all should be `true`. If any are `false`, probe misconfigured or model-load > `initialDelaySeconds + periodSeconds * failureThreshold`.
2. Check decode log for `Backend LIBFABRIC was instantiated`. If it says UCX, the `kv_connector_extra_config` JSON is missing or malformed.
3. Check client request has explicit `stream:true` or `stream:false`. If `curl` omits it, expect the `unit variant` deserialize error.
4. For deeper failures, see the rev7 evidence bundle for a known-good snapshot.
