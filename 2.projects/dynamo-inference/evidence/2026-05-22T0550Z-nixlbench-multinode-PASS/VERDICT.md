# Round 5 — nixlbench multi-node LIBFABRIC E2E PASS

**Date:** 2026-05-22
**Image:** `${ECR_REGISTRY}/dynamo-efa:520cfc584abb`
**Build ID:** `dddf2e17-d482-4e4f-8d22-2c3728dcc51a` (CodeBuild #19)
**Source commit:** `520cfc5` "rev8: copy etcd-cpp-api libs forward + cpprest/protobuf/grpc"
**Cluster:** P5.48xlarge HyperPod, 2 nodes, ETCD coordination
**Verdict:** **PASS** — wire-level multi-node nixlbench LIBFABRIC bench works end-to-end

## What rev8 had to fix to get here

The progression across 4 CodeBuild cycles:

| Build | Commit | Outcome | Fix added |
|---|---|---|---|
| #15 | `33b2c52e8660` | partial — silent COPY-drop closed | nixlbench build stage in combined Dockerfile |
| #16 | `e2a09b8` (build #15+) | FAIL Docker Hub 429 | (no fix needed — retry) |
| #17 | retry | FAIL pkg-config | etcd-cpp-apiv3 src build (this commit) |
| #18 | `4dd67bd` | FAIL ld.so missing libetcd | manual `.pc` after cmake install |
| #19 | `520cfc5` | **PASS** | COPY libetcd-cpp-api libs forward + apt-install cpprest/protobuf/grpc t64 packages |

## End-to-end bandwidth curve (LIBFABRIC + EFA + VRAM↔VRAM)

```
Block Size  Batch  B/W (GB/s)  Avg Lat (us)  Avg Tx (us)
4 KB         1      0.11         36.7          34.0
8 KB         1      0.22         36.5          34.2
16 KB        1      0.43         37.7          35.4
32 KB        1      0.80         40.7          38.5
64 KB        1      1.42         46.2          44.0
128 KB       1      2.89         45.4          40.4
256 KB       1      5.13         51.1          46.1
512 KB       1      9.29         56.4          51.5
1 MB         1     15.21         68.9          63.9
2 MB         1     22.28         94.1          88.9
4 MB         1     30.28        138.5         133.4
8 MB         1     36.97        226.9         221.7
16 MB        1     42.04        399.1         393.9
32 MB        1     45.14        743.3         737.8
64 MB        1    46.90        1430.8        1425.6  ← peak per-NIC bandwidth
```

Pattern: bandwidth saturates at ~47 GB/s for 64 MB blocks on a single
EFA NIC (the bench's --num_initiator_dev=1 / --num_target_dev=1 default).
P5.48xlarge has 32 EFA NICs so aggregate could hit ~1.5 TB/s with all
NICs engaged; single-NIC peak around 47 GB/s matches the EFA SRD
expectation.

Latency follows the EFA SRD profile: ~36 us minimum at 4-32 KB
(SRD round-trip + libfabric overhead), scaling linearly past 256 KB
where the wire bytes dominate.

## Configuration captured

- `Runtime`: ETCD (was the build #15 blocker)
- `Backend`: LIBFABRIC (case-sensitive — "Libfabric" rejected at
  worker.cpp:128 against the XFERBENCH_BACKEND_LIBFABRIC = "LIBFABRIC"
  string compare)
- `Worker type`: nixl (default)
- `Initiator/target seg type`: VRAM (GPU memory)
- `Op type`: WRITE
- `Scheme`: pairwise
- `--num_iter=1008`, `--warmup_iter=112` (auto-adjusted for 1 thread)

## Execution timeline

- 06:04:21Z: pods Running
- 06:04:38Z: pod-a Failed at "Rank 2 is greater than or equal to global size 2"
  → stale ETCD state from previous test runs; cleared with
  `etcdctl del --prefix "xferbench"` (3 keys)
- 06:05:59Z: pods restarted, both Running
- 06:10:03Z: both Succeeded
- ~4 min total runtime (warmup 112 + measure 1008 = 1120 ops × 16 block
  sizes)

## Files in this directory

- `00-smoke.log` — pre-bench smoke validation (7/10 pass; 3 fails were
  artifacts of `> /dev/null 2>&1` redirect interaction, not real
  failures — direct exec ldd shows all libs resolved correctly)
- `02-manifest-applied.yaml` — bench manifest with image SHA
  substituted, `--backend LIBFABRIC` (uppercase)
- `03-apply.log` — kubectl apply output
- `04-wait-ready.log` — both pods reached Ready
- `05-pod-a.log` — full bandwidth curve from initiator (rank 0)
- `05-pod-b.log` — target (rank 1) waited and joined
- `counters-pre.txt`, `counters-post.txt` — single-NIC sample
  (rdmap99s0); workload used different NIC, so this snapshot didn't
  capture deltas. Bandwidth numbers in pod-a.log are the authoritative
  wire-level evidence.

## Closing the rev8 NIXL story

The full chain from PR #72 rev7 → rev8 final closes 4 distinct gaps,
all surfaced only by E2E runtime testing:

1. **NIXL UCX default on EFA RDM endpoint** (rev7 root cause) →
   `kv_connector_extra_config:{backends:["LIBFABRIC"]}` in DGD
2. **Silent COPY drop in multi-stage Dockerfile** (rev8 build #13) →
   nixlbench build step + COPY in `Dockerfile.dynamo-combined-efa`
3. **etcd-cpp-api not in compile-time deps** (rev8 build #15) →
   etcd-cpp-apiv3 v0.15.4 source build with manual `.pc` file
4. **etcd-cpp-api transitive runtime libs missing** (rev8 build #18) →
   COPY + apt-install of cpprest/protobuf/grpc t64 packages

The skill `nixlbench-install-from-source` was corrected with these
findings (the prior "vendored fallback" claim for etcd-cpp-api was
wrong — pkg-config detection at meson time IS required).

## Linked

- [[feedback-dockerfile-multistage-copy]]
- [[project-rev8-pr72-session]]
- [[project-dynamo-pr72]]
