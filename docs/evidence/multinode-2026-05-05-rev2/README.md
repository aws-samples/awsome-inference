# Post-fix validation — dynamo-efa:a1725d43e5c0 (rev2)

Run: 2026-05-05 22:41 → 23:06 UTC, on 2× p5.48xlarge H100 nodes.

## Context

After ce21673 + a1725d4 (NIXL plugin + Dynamo 0.16 + nccl-tests fixes),
re-ran the full validation suite to confirm the fixes landed.

**Image:** `058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-efa:a1725d43e5c0` (23.6 GB).

## Results

| Gate | Result vs d35812d baseline | Evidence |
|---|---|---|
| T1 image in ECR | PASS (unchanged) | ECR describe |
| T2 image size 23.6 GB | PASS (unchanged) | |
| T3 NCCL fat-binary sm_80..sm_120 | PASS (unchanged) | `tests/out/a1725d43e5c0/nccl-arches.txt` |
| T4 EFA devices 96 | PASS (unchanged) | |
| T5 `/v1/models` 200 after 80 s | PASS (unchanged) | |
| T6 `/v1/completions` 890 ms on opt-125m | PASS (unchanged) | |
| T7 RDMA hw_counters > 0 | PASS (unchanged) | |
| T8 no NCCL WARN | PASS (unchanged) | |
| T9 SBOM present | PASS (unchanged) | |
| T10 teardown ≤ 60 s | PASS (unchanged) | |
| **T11 NCCL AllReduce 16-rank cross-node** | **PASS** 322 GB/s busbw at 1 GiB | `t11-r0.log` |
| T11b nccl-tests all_reduce_perf intra-node | **PASS (new)** 357 GB/s busbw single-node 8-GPU | (was missing binary on d35812d) |
| **T12 NIXL plugin load** | **PASS (new)** — no "No plugins available" crash | `t12-prefill-full.log` |
| **T12 Dynamo disagg `--kv-transfer-config`** | **PASS (new)** — arg accepted, workers register etcd endpoints | `t12-prefill-full.log` |
| T12 `/v1/completions` end-to-end | **BLOCKED** (routing issue — separate follow-up) | `t12-dgds.txt` |

## Key evidence of the fixes landing

**nccl-tests binary exists:**
```
$ kubectl exec nccl-allreduce-0 -- ls -la /opt/nccl-tests/bin/all_reduce_perf
-rwxr-xr-x. 1 root root 37151288 May  5 22:08 /opt/nccl-tests/bin/all_reduce_perf
```

**NIXL_PLUGIN_DIR points at pip wheel path:**
```
$ kubectl exec nccl-allreduce-0 -- printenv NIXL_PLUGIN_DIR
/opt/dynamo/venv/lib/python3.12/site-packages/.nixl_cu12.mesonpy.libs/plugins
$ kubectl exec nccl-allreduce-0 -- ls $NIXL_PLUGIN_DIR
libplugin_AZURE_BLOB.so  libplugin_GDS.so  libplugin_GPUNETIO.so
libplugin_GDS_MT.so      libplugin_GUSLI.so  libplugin_LIBFABRIC.so
libplugin_OBJ.so  libplugin_POSIX.so  libplugin_UCX.so
```

**Prefill worker booted without NIXL error:**
```
[INFO] main.init_prefill: Registered engine routes: /engine/sleep, /engine/wake_up
[INFO] main.register_vllm_model: Getting engine runtime configuration metadata from vLLM engine for prefill...
[INFO] main.get_engine_cache_info: Cache config values: {'num_gpu_blocks': 25781, 'block_size': 16}
[INFO] dynamo_runtime::pipeline::network::manager: TCP request plane server started
[INFO] _core: Registered base model 'meta-llama/Llama-3.1-8B-Instruct' MDC
```

Zero occurrences of `"No plugins available for NIXL"` in the log (vs crashing on the first attempt).

## Remaining issue (NOT a Dockerfile bug)

Frontend lists `data: []` because the Dynamo operator auto-renames each DGD's
`dynamoNamespace` field to `<k8s-namespace>-<dgd-name>-<service>` — so the 3
DGDs register under DIFFERENT Dynamo namespaces and Frontend never sees the
workers' model registration.

```
Warning: spec.services[Frontend].dynamoNamespace is deprecated and ignored.
         Value 'dynamo-combined-vllm' will be replaced with
                'default-dynamo-combined-vllm-frontend'. Remove this field
         from your configuration
```

**Fix for follow-up:** Either merge the 3 DGDs into a single DGD with 3 services
(so the operator stamps one namespace on all three), OR manually set the
`DYN_NAMESPACE` env var on each worker/frontend to a shared value like
`default-dynamo-combined-vllm`. The canonical upstream `disagg.yaml`
(`ai-dynamo/dynamo/examples/backends/vllm/deploy/disagg.yaml`) uses a single
DGD with multiple services precisely to avoid this issue.

## Artifacts

| File | Purpose |
|---|---|
| `t11-torch-allreduce.py` | the 16-rank sweep harness |
| `t12-dgd-applied.yaml` | exact YAML applied (HF token redacted) |
| `t12-prefill-full.log` | prefill worker boot + endpoint register (NO NIXL error) |
| `t12-decode-full.log` | decode worker boot (same pattern) |
| `t12-pods.txt` | final pod state |
| `t12-dgds.txt` | final DGD Ready state |

## What this unblocks

- Anton can merge PR #72 knowing the NIXL and nccl-tests bugs are fixed in-image.
- The DGD namespace merge is a small YAML refactor (no image rebuild).
- 1.0.1 → 1.0.2 bump remains pending NVIDIA go-ahead.

## Constraints honored

- H100 only (p5.48xlarge)
- `~/.claude/cluster-lock-h100.json` held throughout, released on completion
- `nvshmem-efa/deepep-nvshmem` scaled 2→0 for run, restored to 2 after
- Image tag was explicit `a1725d43e5c0` (never `latest`)
