# T12 /v1/completions end-to-end — single-DGD attempt (2026-05-05 rev3)

Run: 2026-05-05 23:40 → 23:58 UTC, on 2× p5.48xlarge H100 nodes.
Image: `058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-efa:a1725d43e5c0`.

## Context

rev2 left T12 `/v1/completions` blocked because three separate DGDs landed
each service under a different auto-stamped `dynamoNamespace`
(`default-dynamo-combined-vllm-frontend`, `-prefill`, `-decode`).

rev3 applies the canonical upstream fix: merge the three DGDs into ONE
DGD with three services, matching
`ai-dynamo/dynamo/examples/backends/vllm/deploy/disagg.yaml`. The
operator then stamps a single suffix on all three services so they
share the same Dynamo namespace.

## What worked

1. **Single DGD applies cleanly.** `kubectl apply -f dgd-dynamo-combined-vllm.yaml`
   creates one DGD with three services instead of three DGDs.
2. **Operator stamps one shared suffix.** All three services landed on
   suffix `23abbdff` on the first reconcile.
3. **All three pods reach Running 1/1 (frontend) or 0/1-Running (workers).**
   No NIXL plugin crashes. No `--connector` parse errors.
4. **Workers register endpoints in etcd under the shared namespace.**
   Prefill and decode both registered `generate`, `clear_kv_blocks`,
   and `worker_kv_indexer_query_dp0` under
   `namespace=default-dynamo-combined-vllm-23abbdff`.
5. **Model weights load on both workers.** 70 GB VRAM consumed,
   25 781 KV blocks allocated per worker.
6. **Model Express / HF download succeeds.** Cache persisted on the
   FSx `dynamo-shared-storage` volume, no re-download on restart.

## What is still blocked — operator namespace-suffix mismatch

Even with the single-DGD pattern, Frontend's discovery query returns
`0 instances` for the model endpoints. Root cause is a split in how
the operator stamps namespaces across service types:

| Service  | `DYN_NAMESPACE` env set by operator | `DYN_NAMESPACE_WORKER_SUFFIX` |
|----------|-------------------------------------|-------------------------------|
| Frontend | `default-dynamo-combined-vllm`      | — (none)                      |
| Workers  | `default-dynamo-combined-vllm`      | `23abbdff` (appended)         |

Workers register under `default-dynamo-combined-vllm-23abbdff`.
Frontend looks under `default-dynamo-combined-vllm`. The two do not
align even though they come from the same DGD.

Manual workaround attempted:

- Patched the DGD to set `DYN_NAMESPACE=default-dynamo-combined-vllm-23abbdff`
  explicitly on the Frontend service. The operator reconciled the
  deployment, new frontend pod rolled out with the correct env.
- Also switched both frontend and workers to `DYN_DISCOVERY_BACKEND=etcd`
  (default was `kubernetes`, which uses operator-managed custom
  resources that are namespace-stamped differently from etcd).

After both changes, the operator regenerated the worker deployments
with a new suffix (`016d6303`) because the service-spec edit changes
the template hash. This invalidated the hard-coded `23abbdff` Frontend
`DYN_NAMESPACE` and the cycle restarted.

**This is an upstream operator design issue.** Any DGD-spec edit
regenerates the worker suffix, so any hard-coded Frontend namespace
override drifts on the next reconcile.

## Recommended follow-up (NOT in this PR)

1. File an upstream issue against `ai-dynamo/dynamo` asking for one of:
   - Frontend `DYN_NAMESPACE` to match `DYN_NAMESPACE_WORKER_SUFFIX`
     by default so the two sides of the discovery handshake align.
   - A `--namespace-suffix` projection the operator computes once per
     DGD and stamps on every service (frontend + workers) identically.
2. Until fixed upstream, the workaround is to pin the suffix in the
   DGD spec (requires a CRD field addition upstream) OR accept that
   T12 `/v1/completions` is blocked on the operator-managed flow and
   fall back to a manual worker-registration pattern.

## What this PR ships

- Merged single-DGD manifest (`dgd-dynamo-combined-vllm.yaml`)
  replaces the 3-DGD structure. This is required upstream and is
  the correct pattern regardless of the namespace issue.
- `a1725d43e5c0` image unchanged — the NIXL + nccl-tests + kv-transfer-config
  fixes from rev2 remain valid.
- All rev2 gates still PASS (T1–T11/T11b + T12 boot). Only T12
  `/v1/completions` end-to-end is blocked pending the upstream
  namespace fix.

## Constraints honored

- H100 only (p5.48xlarge)
- `~/.claude/cluster-lock-h100.json` held throughout, released on completion
- `nvshmem-efa/deepep-nvshmem` scaled 2 → 0 for run, restored to 2 → 2 after
- Image tag was explicit `a1725d43e5c0` (never `latest`)
