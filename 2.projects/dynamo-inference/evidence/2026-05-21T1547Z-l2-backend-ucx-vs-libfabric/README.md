# L2 backend comparison — UCX vs LIBFABRIC on EFA

**TL;DR:** Wire-level comparison proving UCX cannot do cross-node on
EFA RDM with `hostNetwork:true` pods, while LIBFABRIC succeeds. Also
documents 5 nixlbench-build attempts that informed the rev8 Dockerfile.

## Why this matters

This is the wire-level companion to the
`2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause` FAIL. That
experiment showed UCX fails at the application layer (NIXL_ERR_BACKEND);
THIS experiment shows WHY at the transport layer.

## Findings

| Backend | Result | Why |
|---|---|---|
| LIBFABRIC | PASS | Binds EFA RDM endpoints; cross-node wire transfer works |
| UCX | FAIL | UCX picks link-local 169.254.0.1 (EC2 metadata IP) on hostNetwork pods; no actual cross-node packets |

The 169.254.0.1 fallback is documented in UCX upstream as a known issue
on AWS EC2 — UCX scans interfaces and picks the first "reachable" one,
but the EC2 metadata IP is not actually a usable cross-node target.

## nixlbench build journey

5 nixlbench-build attempts captured in `artifacts/nixlbench-setup*.log`.
None succeeded at this point — they're the source-of-failure that
motivated the rev8 Dockerfile changes (source-build of
etcd-cpp-apiv3, manual `.pc` file, runtime t64 packages). The first
working build was rev8 build #19, validated in
`../2026-05-22T0550Z-nixlbench-multinode-PASS/`.

## Files

- `manifest.yaml` — status: PARTIAL (LIBFABRIC PASS, UCX FAIL)
- `artifacts/libfabric-client.log`, `libfabric-server.log` — wire test PASS
- `artifacts/nixlbench-{build,meson-setup,setup,setup-attempt2,setup3}.log` — 5 build attempts (all FAIL at this point)

## Linked

- Application-layer FAIL: `../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/`
- Working nixlbench build: `../2026-05-22T0550Z-nixlbench-multinode-PASS/`
