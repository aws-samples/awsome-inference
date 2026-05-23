# rev8 PR #72 evidence — top-level index

This directory contains the full validation trail for the rev8 image
`${ECR_REGISTRY}/dynamo-efa:520cfc584abb`
(CodeBuild #19, source commit `520cfc5` on `feature/dynamo-combined-vllm-trtllm-efa`
in `dmvevents/awsome-inference-1`).

The image is the **first rev8 build** that passes ALL of:
- nixlbench wire-level cross-node bench
- T11 `/v1/models`
- T12 `/v1/completions` cross-node disaggregated
- KV router (aggregated and disaggregated)

## Build chain (5 CodeBuild cycles to reach the working image)

| Build | Commit | Result | Lesson |
|---|---|---|---|
| #15 | `33b2c52` | partial | Closed silent-COPY-drop bug; surfaced 2 new gaps |
| #16 | (retry of `e2a09b8`) | FAIL Docker Hub 429 | Transient — retry |
| #17 | `e2a09b8` | FAIL pkg-config | etcd-cpp-apiv3 needs source build (no Ubuntu pkg) |
| #18 | `4dd67bd` | FAIL exit 127 | etcd-cpp-apiv3 CMake doesn't ship .pc — write manually |
| #19 | `520cfc5` | **PASS** | Runtime libs (cpprest/protobuf/grpc) needed in trtllm/vllm stages |

## Round-by-round validation

| Round | Date | Verdict | Headline | Files |
|---|---|---|---|---|
| 1-3 | 2026-05-21 | rev7 baseline analysis | NIXL UCX hardcode root-cause; LIBFABRIC fix in DGD | `01-*` … `09-*`, `COVERAGE-MATRIX.md`, `SUMMARY.md`, `TEAM-FINDINGS.md` |
| round2-libfabric-forced | 2026-05-21 | first LIBFABRIC PASS | Decode worker no longer crashes with NIXL_ERR_BACKEND | `round2-libfabric-forced/` |
| round3-l2-backend-comparison | 2026-05-21 | UCX vs LIBFABRIC L2 | UCX cross-node fails on EFA RDM (link-local 169.254.0.1); LIBFABRIC works | `round3-l2-backend-comparison/` |
| round4-nixlbench-multinode | 2026-05-21 | partial (build #15) | Silent-COPY-drop fix confirmed; 2 new gaps surfaced | `round4-nixlbench-multinode/` |
| **round5-nixlbench-PASS** | 2026-05-22 | **PASS** | nixlbench 46.9 GB/s @ 64MB single-NIC peak | `round5-nixlbench-PASS/` |
| **round6-disagg-T11-T12** | 2026-05-22 | **PASS** | T11 + T12 cross-node 1.886s HTTP 200 | `round6-disagg-T11-T12/` |
| **round7-config-matrix** | 2026-05-22 | **2/2 KV-router PASS** | agg 7×, disagg 15.6× prefix-cache speedup | `round7-config-matrix/` |

## Reproduce links

- `round5-nixlbench-PASS/REPRODUCE.md` — every command for the wire-level bench
- `round6-disagg-T11-T12/REPRODUCE.md` — DGD deploy + endpoint test
- `round7-config-matrix/REPRODUCE.md` — KV-router config patches + 3 deferred-config rationales

## Headline numbers

| Test | Result |
|---|---|
| nixlbench LIBFABRIC peak BW (single EFA NIC) | **46.9 GB/s @ 64 MB** |
| Disagg /v1/completions cold (no router) | 1.886 s |
| Disagg /v1/completions cold (KV router) | 1.872 s |
| Disagg /v1/completions prefix-match (KV router) | **0.120 s — 15.6× speedup** |
| Agg /v1/completions cold (KV router) | 0.752 s |
| Agg /v1/completions prefix-match (KV router) | **0.108 s — 7.0× speedup** |
| Cross-node KV transfer | NIXL LIBFABRIC over EFA RDMA, confirmed |

## Deferred / out of scope

- **KVBM**: needs LIBFABRIC-preserving variant of upstream `disagg_kvbm.yaml`
- **TRT-LLM**: combined Dockerfile DGD layout creates 3 separate DGDs; needs single-DGD restructure
- **SGLang**: SGLang stage not in `Dockerfile.dynamo-combined-efa`; Dockerfile work needed

## Skills extracted from this session

- `~/.claude/skills/dynamo-deploy-disagg-on-efa/SKILL.md` — DGD deploy pattern with NIXL LIBFABRIC + readinessProbe
- `~/.claude/skills/dynamo-kv-router-validation/SKILL.md` — 3-prompt prefix-cache test pattern
- `~/.claude/skills/nixlbench-multinode-on-efa/SKILL.md` — End-to-end run-multinode.sh recipe (updated from existing)
- Existing `nixlbench-install-from-source/SKILL.md` corrected with the etcd-cpp-api requirement

## Pushes

| Repo | Branch | Commit | Contents |
|---|---|---|---|
| `dmvevents/awsome-inference-1` | `feature/dynamo-combined-vllm-trtllm-efa` | `520cfc5` | Dockerfile.dynamo-combined-efa: etcd-cpp-apiv3 src build + manual .pc + runtime libs |
| `dmvevents/awesome-inferencing` | `main` | `300b20b` | round 4 verdict |
| `dmvevents/awesome-inferencing` | `main` | `f694948` | round 5 PASS |
| `dmvevents/awesome-inferencing` | `main` | `432a290` | round 6 PASS |
| `dmvevents/awesome-inferencing` | `main` | `9a159e5` | round 7 PARTIAL-PASS |
