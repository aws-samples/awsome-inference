# rev7 baseline — NIXL UCX-default root cause investigation (FAIL)

**TL;DR:** Diagnostic experiment that proved vLLM's NixlConnector defaults
to UCX, which crashes on EFA RDM endpoints. Motivated the LIBFABRIC fix
that downstream PASS experiments depend on.

## Why this experiment matters

This is the citation for every "why we force LIBFABRIC" decision. It
documents the actual decode-worker crash trace, the prefill log, and
the as-deployed DGD that triggered the bug.

## What happened

- 3 pods deployed (Frontend + PrefillWorker + DecodeWorker) on rev7
  image, default NixlConnector config
- PrefillWorker started successfully and registered KV cache with NIXL
- First `/v1/completions` request: DecodeWorker tried to load remote
  metadata via NIXL → `NIXL_ERR_BACKEND`
- HTTP response masked the real cause: a `HTTP 500 invalid type: unit
  variant` (Dynamo 1.1.0 `handlers.py` emits bare `finish_reason:"error"`
  which the Rust `FinishReason::Error` newtype rejects)

## Root cause

`vllm/distributed/kv_transfer/kv_connector/v1/nixl_connector.py:1022`
hardcodes `backends=["UCX"]` as the default. UCX cannot bind EFA RDM
endpoints (UCX requires reliable connections; EFA RDM is unreliable
datagram). Decode worker crashes when it tries to dial the prefill
worker's NIXL agent.

## Fix

Add `kv_connector_extra_config:{backends:["LIBFABRIC"]}` to the
`--kv-transfer-config` JSON in the DGD manifest. Validated in
`2026-05-21T1539Z-rev7-libfabric-forced-PASS/`.

## Files

- `manifest.yaml` — status: FAIL
- `VERDICT.md`, `REPRODUCE.md`
- `artifacts/05-decode-crash.log` — the actual crash trace
- `artifacts/06-prefill.log` — prefill side (worked)
- `artifacts/07-frontend.log` — Frontend log
- `artifacts/09-dgd-as-deployed.yaml` — manifest as deployed
- `derived/SUMMARY.md` — early analysis
- `derived/TEAM-FINDINGS.md` — diagnostic narrative
- `derived/COVERAGE-MATRIX.md` — what was tested
- `derived/L1-fi_pingpong-{client,server}.log` — wire-level EFA test (passed)
- `derived/L2-ucx_perftest-{client,server}-FAIL.log` — UCX cross-node failed (link-local 169.254.0.1)
