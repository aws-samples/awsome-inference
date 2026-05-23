# rev7 LIBFABRIC-forced PASS — first proof the NIXL backend override works

**TL;DR:** Same hardware + same image as the FAIL baseline, but with
`kv_connector_extra_config:{backends:["LIBFABRIC"]}` applied. Decode worker
no longer crashes; `/v1/completions` returns HTTP 200.

## Why this matters

This experiment validated the fix that all subsequent rev8 PASS
experiments depend on. It's the smallest possible change demonstrating
that NIXL's LIBFABRIC backend handles EFA RDM endpoints correctly,
where UCX cannot.

## What changed vs the FAIL experiment

Single line in the DGD YAML:

```diff
- --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}'
+ --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both","kv_connector_extra_config":{"backends":["LIBFABRIC"]}}'
```

Everything else identical: same image (`dynamo-efa:9467d1460c71`), same
nodeSelectors, same readinessProbe, same NIXL_BACKEND env vars
(no-ops), same model.

## What this proved

- vLLM's NixlConnector accepts the `kv_connector_extra_config.backends`
  override at construction time
- NIXL's LIBFABRIC backend correctly initializes on EFA RDM
- Cross-node KV transfer succeeds; decode worker generates output

## Files

- `manifest.yaml` — status: PASS
- `artifacts/02-apply.log`, `artifacts/03-wait.log` — deploy trace
- `artifacts/04-models.json` — `/v1/models` response
- `artifacts/05-completion.json` — `/v1/completions` HTTP 200
- `artifacts/counters-r2-pre.txt`, `counters-r2-post.txt` — EFA hw_counter delta

## Linked

- Predecessor (the FAIL): `../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/`
- Wire-level proof of why UCX fails: `../2026-05-21T1547Z-l2-backend-ucx-vs-libfabric/`
- Carried forward in rev8: `../2026-05-22T0900Z-disagg-T11-T12-PASS/`
