# Verdict — rev7 LIBFABRIC PASS

**Result:** PASS — The single-line `kv_connector_extra_config` fix
unblocks cross-node disaggregated inference on EFA.

## Outcome

| Step | Result |
|---|---|
| Apply DGD with LIBFABRIC override | OK |
| 3 pods Ready (Frontend + Prefill + Decode) | OK, ~3 min |
| `/v1/models` | OK |
| `/v1/completions` cross-node | **HTTP 200**, semantically correct output |
| EFA hw_counters (rdma_read_bytes delta) | non-zero (NIXL libfabric uses fi_read) |

See `artifacts/05-completion.json` for the actual completion response.

## Significance

This is the **fix-validated** companion to the FAIL baseline. Together,
they establish:

1. The bug: vLLM NixlConnector hardcodes UCX (FAIL experiment)
2. The fix: kv_connector_extra_config.backends LIBFABRIC override (THIS experiment)

Every subsequent rev8 experiment in this campaign carries this fix
forward. Removing it would re-introduce the rev7 baseline FAIL.

## Linked

- Predecessor FAIL: `../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/`
- Wire-level: `../2026-05-21T1547Z-l2-backend-ucx-vs-libfabric/`
- rev8 final PASS: `../2026-05-22T0900Z-disagg-T11-T12-PASS/`
