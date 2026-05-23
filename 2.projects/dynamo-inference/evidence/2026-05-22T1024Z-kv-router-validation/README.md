# KV router validation — vLLM agg + disagg

**TL;DR:** Both KV-router-enabled vLLM configs PASS on the rev8 image with measurable prefix-cache speedups: **disagg-router 15.6×, agg-router 7.0×**. KVBM and TRT-LLM/SGLang variants deferred with documented reasons.

## Why this experiment exists

After round 6 proved the baseline disagg path works, this experiment validates the headline upstream Dynamo features layered on top:
- `DYN_ROUTER_MODE=kv` — KV-aware request routing
- `--kv-events-config` — ZMQ event publisher for the router to subscribe to
- KV events transport via NATS

The single most-feature-rich config in the upstream `examples/backends/vllm/deploy/disagg_router.yaml`.

## Sub-experiments

| Sub-experiment | Topology | Status | Cold Q1 | Prefix-match Q2 | Speedup |
|---|---|---|---|---|---|
| `vllm-disagg-router-PASS/` | cross-node disagg | **PASS** | 1872 ms | **120 ms** | **15.6×** |
| `vllm-agg-router-PASS/` | single-pod agg | **PASS** | 752 ms | **108 ms** | **7.0×** |
| `derived/superseded/vllm-disagg-kvbm/` | (KVBM) | DEFERRED | — | — | — |
| `derived/superseded/trtllm-disagg/` | (TRT-LLM) | DEFERRED | — | — | — |

Failed first-attempt directories are kept under `derived/superseded/` as cautionary tales (see VERDICT.md for the operator-label bug that wasted the first attempt).

## What this proved

The 7×–15.6× latency reduction on Q2 (same prefix as Q1) is wire-level proof that the KV router cached and reused the prefix. Frontend logs from both PASS configs show all 5 required activation messages.

## Why some configs are deferred

- **KVBM**: upstream `disagg_kvbm.yaml` drops the `kv_connector_extra_config.backends:LIBFABRIC` override, which is unsafe on EFA (UCX default crashes on RDM endpoints — the rev7 root cause). Needs a LIBFABRIC-preserving variant authored.
- **TRT-LLM**: combined-efa DGD layout splits services into 3 separate DGDs with different `dynamoNamespace` stamps; Frontend's KubeDiscoveryClient can't cross-discover. Needs single-DGD restructure.
- **SGLang**: combined-efa Dockerfile has no SGLang stage; Dockerfile work needed.

See `VERDICT.md` for full analysis.

## Files

- `manifest.yaml` — campaign-level metadata (PARTIAL status)
- `VERDICT.md`
- `REPRODUCE.md`
- `vllm-disagg-router-PASS/` — sub-experiment with its own dgd.yaml + logs (renamed from `-v2/`)
- `vllm-agg-router-PASS/` — sub-experiment (renamed from `-v2/`)
- `derived/superseded/{vllm-agg-router,vllm-disagg-router,vllm-disagg-kvbm,trtllm-disagg}/` — first-attempt failed dirs preserved
- `derived/run-matrix.sh` — original automated runner (had label-selector bug; kept for reference)
- `derived/runner.log` — failed first-attempt output
- `derived/SUMMARY.md` — early synthesis (superseded by VERDICT.md)
