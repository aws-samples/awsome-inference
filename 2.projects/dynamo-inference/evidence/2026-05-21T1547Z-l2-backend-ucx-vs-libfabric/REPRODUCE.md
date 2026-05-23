# Reproduce: L2 backend comparison

**Goal:** Verify on your cluster that UCX cross-node fails on EFA RDM
endpoints under `hostNetwork:true`, while LIBFABRIC succeeds.

## Environment

Same as the rev7 baseline (`../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/`).

## Reproduce — LIBFABRIC leg (should PASS)

1. Deploy 2 pods with `hostNetwork:true` on different P5 nodes.
2. From one pod (server):
   ```bash
   fi_pingpong -p efa
   ```
3. From the other pod (client):
   ```bash
   fi_pingpong -p efa <server-pod-ip>
   ```

Expected: clean handshake + bidirectional ping output. See
`artifacts/libfabric-client.log` for the canonical run.

## Reproduce — UCX leg (should FAIL)

1. Same 2 pods.
2. Server:
   ```bash
   ucx_perftest -t put_lat
   ```
3. Client:
   ```bash
   ucx_perftest -t put_lat <server-pod-ip>
   ```

Expected: UCX picks 169.254.0.1 (link-local), test never establishes
cross-node connection. See `artifacts/L2-ucx_perftest-client-FAIL.log`
for canonical run.

## Why the failure

UCX scans network interfaces in priority order. On a HyperPod EKS pod
with `hostNetwork:true`, the EC2 metadata interface (169.254.0.1)
shows up as "reachable" — UCX picks it. Actual EFA fabric is
configured but not chosen.

## Files

- `artifacts/libfabric-client.log`, `libfabric-server.log` — LIBFABRIC PASS
- `artifacts/nixlbench-*.log` — 5 nixlbench build attempts (FAIL at this point)
