# Validation evidence

This directory's `evidence/` subdir contains the validation trail for
this PR. It is a **sanitized, parametric copy** of the canonical
ground-truth archive at:

> **`dmvevents/awesome-inferencing` → `docs/evidence/pr72-rev8/`**

The canonical archive contains the full raw artifacts (kubectl logs,
hw_counters, completion responses, as-deployed YAMLs). Here we ship
only the queryable summary: per-experiment `manifest.yaml` + README +
VERDICT + REPRODUCE + parametric `derived/dgd-template.yaml`. Account
numbers and hostnames are stripped per `evidence/SANITIZATION.md`.

## What's in `evidence/`

```
evidence/
├── README.md         ← campaign summary
├── PREREQUISITES.md  ← cluster setup
├── BUILD.md          ← image build trigger
├── SCHEMA.md         ← manifest.yaml schema
├── SANITIZATION.md   ← substitution rules
└── 2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/   ← 7 experiments by datetime + slug
    ├── manifest.yaml
    ├── README.md, VERDICT.md, REPRODUCE.md
    └── derived/  ← parametric templates (dgd-template.yaml etc.)
```

## Reproducing any experiment

1. Set parameters:
   ```bash
   export ECR_REGISTRY="<your registry>"
   export IMAGE_TAG="520cfc584abb"
   ```
2. Read `evidence/<datetime-slug>/REPRODUCE.md` for that experiment.
3. Use `evidence/<datetime-slug>/derived/dgd-template.yaml` as the
   parametric Kubernetes manifest (substitute `${ECR_REGISTRY}` and
   `${IMAGE_TAG}` via `envsubst`).

## Where to find the raw artifacts

Each experiment's `manifest.yaml` lists the artifacts it produced. The
actual file contents live in the canonical archive:

```
dmvevents/awesome-inferencing
  → docs/evidence/pr72-rev8/<datetime-slug>/artifacts/
```

## Update flow

When experiments are re-run, the canonical archive is updated FIRST,
then this directory is synced from it. Do not edit `evidence/` here
directly — it will be overwritten on next sync.

See `awesome-inferencing/docs/evidence/SANITIZATION.md` for the exact
sync recipe.

## Headline numbers

| Capability | Status | Where |
|---|---|---|
| Wire-level NIXL LIBFABRIC over EFA | **PASS** — 46.9 GB/s @ 64 MB | `evidence/2026-05-22T0550Z-nixlbench-multinode-PASS/` |
| Disaggregated `/v1/completions` cross-node | **PASS** — 1.886s | `evidence/2026-05-22T0900Z-disagg-T11-T12-PASS/` |
| KV router on disagg | **PASS** — 15.6× prefix-cache speedup | `evidence/2026-05-22T1024Z-kv-router-validation/vllm-disagg-router-PASS/` |
| KV router on agg | **PASS** — 7.0× prefix-cache speedup | `evidence/2026-05-22T1024Z-kv-router-validation/vllm-agg-router-PASS/` |
| KVBM, TRT-LLM, SGLang configs | DEFERRED | see `evidence/2026-05-22T1024Z-kv-router-validation/VERDICT.md` |

Build chain (5 CodeBuild cycles to reach PASS):

| Build | Source | Outcome |
|---|---|---|
| #15 | `33b2c52` | partial (silent-COPY-drop fix; 2 new gaps) |
| #16 | retry of `e2a09b8` | FAIL Docker Hub 429 |
| #17 | `e2a09b8` | FAIL pkg-config |
| #18 | `4dd67bd` | FAIL exit 127 |
| #19 | `520cfc5` | **PASS** — `dynamo-efa:520cfc584abb` |
