# Wire-level NIXL LIBFABRIC bench across 2 P5 nodes

**TL;DR:** Proves NIXL's LIBFABRIC backend transfers VRAM↔VRAM cross-node over EFA RDMA at **46.9 GB/s peak per single EFA NIC** (block size 64 MB).

## Why this experiment exists

Before testing any inference workload, we need wire-level proof that the NIXL transport itself works on this image. Separates "is the transport broken?" from "is the application broken?". This is the prerequisite that informed all subsequent serving experiments in this campaign.

## What it does

Runs `nixlbench v1.0.1` cross-node (2 pods, 1 per node, anti-affinity by hostname). Both pods register with the platform ETCD service; rank 0 pulls KV blocks from rank 1 across 15 block sizes (4 KB → 64 MB) using the LIBFABRIC backend.

## What this proved

- The rev8 image's `nixlbench` binary loads all transitive runtime libs (libgflags2.2, libtomlplusplus3, libetcd-cpp-api, libcpprest, libprotobuf, libgrpc) — closes the rev8 build #15 and #18 gaps
- The LIBFABRIC backend is registered at compile time (etcd-cpp-apiv3 source build + manual `.pc` worked)
- ETCD coordination across pods works
- Bandwidth saturates around the EFA SRD per-NIC ceiling (~47 GB/s)
- Latency floor is ~36 µs at 8 KB

See `VERDICT.md` for the full bandwidth curve. See `REPRODUCE.md` for exact commands.

## Files

- `manifest.yaml` — machine-readable metadata (queryable via `yq`)
- `VERDICT.md` — full bandwidth curve + analysis
- `REPRODUCE.md` — exact commands to re-run from scratch
- `EXPECTATIONS.md` — pre-run predictions (kept as a sanity check on what was expected vs what we got)
- `artifacts/00-smoke.log` — pre-bench smoke validation (10 checks)
- `artifacts/02-manifest-applied.yaml` — actual K8s manifest applied
- `artifacts/03-apply.log` — `kubectl apply` output
- `artifacts/04-wait-ready.log` — pod readiness wait
- `artifacts/05-pod-a.log` — full bandwidth curve from initiator pod (rank 0)
- `artifacts/05-pod-b.log` — target pod (rank 1) — joined and barriered
