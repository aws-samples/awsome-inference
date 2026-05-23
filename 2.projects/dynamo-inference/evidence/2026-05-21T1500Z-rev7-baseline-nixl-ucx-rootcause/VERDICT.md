# Verdict — rev7 baseline FAIL: NIXL UCX-default root cause

**Result:** FAIL — DecodeWorker crashed on first `/v1/completions` request
with `NIXL_ERR_BACKEND` because vLLM's NixlConnector defaulted to UCX.

## Why this is a critical FAIL

A FAIL with a clean root cause is more valuable than a green CI run.
This experiment is cited from every downstream PASS verdict as the
motivation for the LIBFABRIC backend forcing.

## The chain of events

1. DGD applied with stock `--kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}'`
2. All 3 pods reached Ready (Frontend, PrefillWorker, DecodeWorker)
3. `/v1/models` returned the model — KubeDiscoveryClient worked
4. First `/v1/completions` request:
   - Frontend forwarded to PrefillWorker — OK (`artifacts/06-prefill.log` line ~120)
   - PrefillWorker computed KV, registered with NIXL agent — OK
   - DecodeWorker attempted to load remote metadata: `loadRemoteMD()` → `NIXL_ERR_BACKEND`
   - DecodeWorker crashed (`artifacts/05-decode-crash.log` line ~340)
5. Frontend received the cascading 500 from Dynamo's runtime layer

## Root cause (verified by source-reading)

`vllm/distributed/kv_transfer/kv_connector/v1/nixl_connector.py:1022-1024`:
```python
self._nixl_handshake_listener_t = threading.Thread(
    target=self._nixl_handshake_listener,
    args=(self.nixl_wrapper, self.side_channel_port, ...,
          ["UCX"]),  # <-- hardcoded default backend list
    daemon=True)
```

The `NIXL_BACKEND` and `VLLM_NIXL_KVCACHE_BACKEND` env vars are NOT
read here — they were never wired through. Only the
`kv_connector_extra_config.backends` field of the `--kv-transfer-config`
JSON is honored.

## Fix (validated in next experiment)

```yaml
args:
  - --kv-transfer-config
  - '{"kv_connector":"NixlConnector","kv_role":"kv_both","kv_connector_extra_config":{"backends":["LIBFABRIC"]}}'
```

## Numbers

| Metric | Value |
|---|---|
| HTTP status (visible) | 500 |
| Real underlying error | NIXL_ERR_BACKEND (decode worker) |
| Prefill request received | yes |
| Prefill KV registered | yes |
| Decode KV transfer | failed |
| Time to crash | <1 second after first POST |

## Linked

- Validated fix: `../2026-05-21T1539Z-rev7-libfabric-forced-PASS/`
- Backend comparison wire-level: `../2026-05-21T1547Z-l2-backend-ucx-vs-libfabric/`
- Final passing image: `../2026-05-22T0900Z-disagg-T11-T12-PASS/`
- Upstream filed issue: `vllm-project/vllm` — NixlConnector hardcoded UCX default
