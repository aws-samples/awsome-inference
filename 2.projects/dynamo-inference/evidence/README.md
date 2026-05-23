# Campaign: pr72-rev8 — Dynamo combined-efa rev8 validation

**PR:** [aws-samples/awsome-inference#72](https://github.com/aws-samples/awsome-inference/pull/72) (head: `dmvevents/awsome-inference-1` branch `feature/dynamo-combined-vllm-trtllm-efa`)
**Headline image:** `${ECR_REGISTRY}/dynamo-efa:520cfc584abb` (CodeBuild #19, source commit `520cfc5`)
**Hardware:** EKS HyperPod, p5.48xlarge × 2 (H100 + 32 EFA NICs/node)
**Date range:** 2026-05-21 → 2026-05-22

## What this campaign proved

| Capability | Result | Evidence |
|---|---|---|
| Wire-level NIXL LIBFABRIC over EFA, VRAM↔VRAM | **46.9 GB/s @ 64MB** (single-NIC peak) | `2026-05-22T0550Z-nixlbench-multinode-PASS/` |
| Aggregated `/v1/models` + `/v1/completions` | PASS | `2026-05-22T0900Z-disagg-T11-T12-PASS/` |
| Disaggregated `/v1/completions` cross-node | PASS, 1.886s HTTP 200 | `2026-05-22T0900Z-disagg-T11-T12-PASS/` |
| KV router on aggregated | PASS, **7.0× prefix-cache speedup** | `2026-05-22T1024Z-kv-router-validation/` |
| KV router on disaggregated cross-node | PASS, **15.6× prefix-cache speedup** | `2026-05-22T1024Z-kv-router-validation/` |

## Build chain (5 CodeBuild cycles to reach the working image)

| Build | Source commit | Outcome | What was learned |
|---|---|---|---|
| #15 | `33b2c52` | partial | Closes silent-COPY-drop; surfaces 2 new gaps |
| #16 | `e2a09b8` (retry) | FAIL Docker Hub 429 | Transient — retry |
| #17 | `e2a09b8` | FAIL pkg-config | etcd-cpp-apiv3 needs source build (no Ubuntu pkg) |
| #18 | `4dd67bd` | FAIL exit 127 | etcd-cpp-apiv3 CMake doesn't ship .pc — write manually |
| **#19** | **`520cfc5`** | **PASS** | Runtime libs (cpprest/protobuf/grpc) needed in trtllm/vllm stages |

The exact `Dockerfile.dynamo-combined-efa`, `Dockerfile.efa`, `buildspec.yml`,
and `build.sh` from commit `520cfc5` are snapshotted in `build-snapshot/`.
This guarantees the build is reproducible even if the upstream branch is
rewritten or deleted.

## Reproduce the whole campaign

1. Read `PREREQUISITES.md` — get cluster, operator, FSx, secrets in place.
2. Read `BUILD.md` — rebuild image SHA `520cfc584abb` (or pull from ECR if still present).
3. Pick an experiment subdir; read its `REPRODUCE.md`; follow the steps.
4. Compare your numbers against the experiment's `VERDICT.md`.

## Experiments in this campaign

(The auto-generated `../INDEX.md` lists every experiment in date order.
This README links them in narrative order.)

1. `2026-05-21T0900Z-rev7-baseline-rootcause/` — root-cause investigation that motivated the rev8 fix
2. `2026-05-21T1138Z-L1-wire-fi_pingpong/` — L1 wire test on EFA
3. `2026-05-21T1410Z-L2-backend-ucx-vs-libfabric/` — L2 backend comparison (UCX fails, LIBFABRIC works)
4. `2026-05-21T1700Z-round2-libfabric-forced/` — first LIBFABRIC PASS (rev7 with manual override)
5. `2026-05-21T2200Z-round4-nixlbench-partial/` — rev8 build #15 partial (gaps surfaced)
6. `2026-05-22T0550Z-round5-nixlbench-PASS/` — rev8 build #19 wire-level PASS
7. `2026-05-22T0900Z-round6-disagg-T11-T12-PASS/` — rev8 build #19 serving PASS
8. `2026-05-22T1024Z-round7-kv-router-validation/` — KV router validation (2/2 PASS, 3 deferred)

## Verification runs (re-runs of canonical experiments)

| Date | Run | Result |
|---|---|---|
| 2026-05-23 | `verification-runs/2026-05-23-Cpass/` | **3/3 PASS** — nixlbench 46.95 GB/s (+0.1%), disagg T12 1.886s (identical), KV router 15.2× speedup (within noise). 1 LOW blocker (B-01 capture-counters path) discovered + RESOLVED. |

Each verification-run subdir is a self-contained re-run of one or more canonical experiments,
using the same image SHA. It documents whether documented `REPRODUCE.md` procedures still
produce equivalent numbers run-to-run. See `verification-runs/<date>-<slug>/REPORT.md` for
the summary table and any blockers encountered.

## Files at this level

- `README.md` — this file
- `PREREQUISITES.md` — cluster/operator/secrets/FSx setup
- `BUILD.md` — exact build trigger commands and expected outputs
- `build-snapshot/` — frozen Dockerfiles, build.sh, buildspec.yml at commit `520cfc5`
- `<datetime-slug>/` — one directory per experiment (see SCHEMA.md at `../SCHEMA.md`)
- `verification-runs/<date>-<slug>/` — re-runs verifying reproducibility of the above
