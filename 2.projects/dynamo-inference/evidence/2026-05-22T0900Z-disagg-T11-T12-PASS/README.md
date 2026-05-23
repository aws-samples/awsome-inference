# Disaggregated inference T11 + T12 baseline (no KV router)

**TL;DR:** Proves NVIDIA Dynamo disaggregated serving (Frontend + PrefillWorker + DecodeWorker) works cross-node on the rev8 image, with KV cache transferred via NIXL LIBFABRIC over EFA RDMA. **HTTP 200 in 1.886s** for a 20-token completion.

## Why this experiment exists

After round 5 proved the wire transport (`nixlbench`), this experiment proves the application path: a real `/v1/completions` request walks Frontend → Prefill → Decode (cross-node KV transfer) → response.

## Topology

| Component | Node | IP |
|---|---|---|
| Frontend | hyperpod-i-0be4f4fec | 10.1.3.82 |
| PrefillWorker | hyperpod-i-0be4f4fec | 10.1.3.151 |
| DecodeWorker | hyperpod-i-0a3eb6d39 | 10.1.3.73 |

Prefill and Decode are on different nodes — KV cache MUST traverse EFA. If LIBFABRIC backend selection were broken, decode would crash with `NIXL_ERR_BACKEND`. It didn't.

## What this proved

- T11 `/v1/models` returns the registered model (Frontend's `KubeDiscoveryClient` discovered the workers via the `nvidia.com/dynamo-graph-deployment-name` label and the readinessProbe-gated EndpointSlices)
- T12 `/v1/completions` cross-node generation succeeds
- The rev7 NIXL UCX-default fix (`kv_connector_extra_config:{backends:["LIBFABRIC"]}`) is preserved in rev8
- Output is semantically correct ("Paris" is the right answer)

## Files

- `manifest.yaml`
- `VERDICT.md`
- `REPRODUCE.md`
- `artifacts/01-dgd-as-deployed.yaml` — DGD manifest with image SHA substituted
- `artifacts/02-apply.log` — kubectl apply output
- `artifacts/03-pods.txt` — pod placement showing cross-node topology
- `artifacts/04-models.json` — T11 response
- `artifacts/05-completion.json` — T12 response (HTTP 200)
