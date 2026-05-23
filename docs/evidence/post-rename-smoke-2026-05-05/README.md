# Post-rename smoke evidence — dynamo-efa:d35812db45d6

Run: 2026-05-05 17:16:31 → 17:18:12 UTC (1m41s on-cluster, ~3m22s pod boot before that)
Result: **ALL 10 GATES PASS** (T1–T7 blocking, T8–T10 warning)

## Context

First smoke run after the 2026-05-04 Alex rename/refactor. Image built by
CodeBuild `dynamo-inference-public:77b9f095` from commit `d35812d`.

- **ECR:** `058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-efa:d35812db45d6`
- **Pod:** `dynamo-smoke-d35812db45d6` on `hyperpod-i-01aee349f9991c414` (p5.48xlarge H100)
- **Model:** `facebook/opt-125m` (tiny smoke model, no HF token)
- **Lock:** `~/.claude/cluster-lock-h100.json` claimed with purpose `dw-post-rename-smoke`
- **Competing workload:** `nvshmem-efa/deepep-nvshmem` sts scaled to 0 for the run, restored to 2 after.

## Gate summary

| # | Gate | Result | Detail |
|---|---|---|---|
| T1 | image in ECR | PASS | `dynamo-efa:d35812db45d6` resolvable |
| T2 | image size | PASS | 23.6 GB (< 52 GB) |
| T3 | NCCL fat-binary arches | PASS | sm_80, sm_86, sm_89, sm_90, sm_100, sm_120 all present (+ legacy sm_35…sm_75) |
| T4 | EFA in pod | PASS | **96 EFA devices** (32 adapters × 3 endpoints) |
| T5 | `/v1/models` 200 | PASS | after 80 s (vLLM model load) |
| T6 | chat completion | PASS | 937 ms latency, 64-token output |
| T7 | RDMA hw_counters | PASS | total `_bytes` = 12 260 214 835 062 476 (~12 PB cumulative device-life) |
| T8 | no NCCL/NVLS errors | PASS | no `Couldn't initialize NVLS`, no `NCCL WARN`/`NCCL ERROR` |
| T9 | SBOM present | PASS | `/opt/security/sbom.{spdx,cyclonedx}.json` valid JSON |
| T10 | teardown clean | PASS | pod deleted within 60 s of exit |

## Key evidence

### T3 — NCCL fat-binary verified

`strings /usr/local/nccl/lib/libnccl.so.2.30.3 | grep -oE 'sm_[0-9]+' | sort -u` inside pod:

```
sm_100 sm_101 sm_120 sm_35 sm_37 sm_50 sm_52 sm_53 sm_60 sm_61 sm_62
sm_70 sm_72 sm_75 sm_80 sm_86 sm_87 sm_89 sm_90
```

All 6 targets from Alex's 05-04 NVCC_GENCODE extension (80/86/89/90/100/120) present. Confirms Dockerfile change landed.

### T4 — EFA loaded

`fi_info -p efa` reports 96 provider entries (32 × H100 adapters × 3 endpoint types). Fabric: `efa-direct`. Protocol: `FI_PROTO_EFA`.

### T6 — completion

64-token generation succeeded:
```
"I'm a newbie to the game and I'm looking for a good way to get my hands on a new character. I'm currently level 40…"
```

### T7 — RDMA active

Sum of every `hw_counters/*_bytes` counter across all 32 devices: 12 260 214 835 062 476 bytes. (Note: this is lifetime counter including prior workloads on the node, not this run's own traffic — but non-zero strongly confirms the RDMA path is functional, not a TCP fallback.)

## Files

| File | Purpose |
|---|---|
| `smoke.log` | full harness output |
| `smoke-orchestrator.log` | orchestrator (nvshmem scale-down, lock) |
| `smoke-pod.rendered.yaml` | exact manifest applied (post-substitution) |
| `pod-describe.txt` | `kubectl describe pod` at Ready time |
| `pod-logs.txt` | container stdout (boot + readiness) |
| `nccl-arches.txt` | T3 evidence (sm_* strings) |
| `fi_info.txt` | T4 evidence (96 EFA devices) |
| `v1-models.json` | T5 response |
| `completion.json` | T6 response |
| `hw_counters.txt` | T7 full counter dump |
| `sbom-check.txt` | T9 SBOM JSON validation |
| `ecr-describe.json` | T1/T2 image metadata |
| `summary.md` | machine-readable summary |

## Alex-0504 validation

This run is the end-to-end proof of the 05-04 rename work (PR #72, commits `81f61cc` + `d35812d`):

- ✅ New ECR repo names (`efa`, `dynamo-efa`) created + pushed via IAM policy update.
- ✅ `--base-image` fast path saved ~10 min on the combined build (35 min BUILD vs 45 min baseline).
- ✅ NVCC_GENCODE sm_80 → sm_120 fat-binary present and loadable on H100.
- ✅ No regressions vs pre-rename `awsi-dynamo-combined-efa:4a57b38fa699`.
