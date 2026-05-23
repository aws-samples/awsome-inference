# T12 end-to-end — rev4 (DYN_NAMESPACE_WORKER_SUFFIX override attempt)

Run: 2026-05-06 00:08 → 00:31 UTC on dynamo-efa:a1725d43e5c0.

## Context

Rev3 (parallel session) committed the single-DGD refactor + merge fixes to
main (b1f64c6). Rev4 experiments with a further override to eliminate the
worker-hash namespace suffix and close T12 end-to-end.

## Approach

Added two env overrides to every DGD service:

```yaml
- { name: DYN_NAMESPACE, value: "default-dynamo-combined-vllm" }
- { name: DYN_NAMESPACE_WORKER_SUFFIX, value: "" }
```

## What changed vs rev3

1. Worker runtime now registers endpoints under `default-dynamo-combined-vllm`
   (no `-<hash>` suffix), matching Frontend's `DYN_NAMESPACE`.

2. EndpointSlice label `nvidia.com/dynamo-namespace` is also stamped without
   the suffix: `default-dynamo-combined-vllm`.

3. Worker pods still carry operator-assigned hash labels (`dynamo-worker-hash`
   = e.g. `4e46d612`) on the pod metadata, but this is irrelevant to Frontend
   discovery since KubeDiscoveryClient queries by namespace.

## Result

Despite the namespace aligning on both sides, Frontend's KubeDiscoveryClient
still returns `0 instances for query=AllEndpoints`. Root cause appears to
be deeper: the daemon watches `DynamoWorkerMetadata CRs in namespace: default`
(k8s namespace) and filters by the Dynamo internal namespace somewhere —
but we do not yet understand the exact filter predicate.

Hypotheses to investigate in rev5:
1. DWM CRs may need the `nvidia.com/dynamo-namespace` label set explicitly
   (the operator may only set it on EndpointSlices, not DWMs).
2. Frontend's daemon may only accept DWMs whose owning Pod has the same
   `nvidia.com/current-worker-hash` annotation as the DGD.
3. There may be an NATS/etcd-side registration step separate from the k8s
   DWM/EndpointSlice stream that requires matching namespaces on the NATS
   side.

## Evidence

- `t12-dgd-applied-rev4.yaml` — exact DGD applied (HF token redacted)
- `t12-pods.txt` — Frontend + Prefill + Decode all Running on correct nodes
- `t12-prefill.log` — shows `namespace=default-dynamo-combined-vllm` registration (no suffix)
- `t12-decode.log` — same, under `component: backend`
- `t12-frontend.log` — `returning 0 instances for query=AllEndpoints` on every 10s poll
- `t12-dwm.txt` — DynamoWorkerMetadata CRs exist without labels
- `t12-endpointslices.yaml` — shows `nvidia.com/dynamo-namespace: default-dynamo-combined-vllm`

## Decision

Pause on rev4. Rev3 (committed to main at b1f64c6) is the best-known-committed
state. The remaining discovery gap is an operator-runtime wiring issue that
needs engineer-to-engineer discussion with the Dynamo team or deeper source
tracing in `dynamo_runtime::discovery::kube::daemon`.

## Cleanup

- DGD deleted
- `nvshmem-efa` restored to 2/2
- `~/.claude/cluster-lock-h100.json` released at 2026-05-06 00:31 UTC
