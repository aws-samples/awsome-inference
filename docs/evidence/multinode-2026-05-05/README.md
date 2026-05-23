# Multi-node evidence — dynamo-efa:d35812db45d6

Run: 2026-05-05 19:51 → 20:26 UTC on 2× p5.48xlarge H100 nodes
(`hyperpod-i-01aee349f9991c414` 10.1.3.30 + `hyperpod-i-0a3eb6d3953cceaa7` 10.1.3.73).

## Results

| Gate | Result | Evidence |
|---|---|---|
| **T11 — NCCL AllReduce 16-rank across 2 nodes** | **PASS** | `t11-results.json`, `t11-rank0-full.log`, `t11-efa-proof.txt` |
| **T12 — Dynamo disaggregated (Frontend + Prefill + Decode)** | **PARTIAL** | `t12-prefill-full.log`, `t12-pods.txt` |

## T11 — NCCL AllReduce (PASS)

16 ranks (8 per pod) × H100 × 2 nodes, `torch.distributed` init over tcp://, backend=nccl.

**Bandwidth sweep (ring AllReduce):**

| size | time | algbw | busbw |
|---|---|---|---|
| 1 MiB | 0.32 ms | 3.3 GB/s | 6.2 GB/s |
| 4 MiB | 0.14 ms | 30.4 GB/s | 57.0 GB/s |
| 16 MiB | 0.35 ms | 48.5 GB/s | 90.9 GB/s |
| 64 MiB | 0.61 ms | 109.2 GB/s | 204.7 GB/s |
| 256 MiB | 1.84 ms | 146.2 GB/s | 274.2 GB/s |
| **1 GiB** | **6.09 ms** | **176.2 GB/s** | **330.4 GB/s** |

### EFA path confirmed

Sample NCCL bringup log lines (`t11-efa-proof.txt`):

```
NCCL INFO Channel 00/0 : 8[0] -> 0[0] [receive] via NET/Libfabric/0/GDRDMA
NCCL INFO Channel 08/0 : 8[0] -> 0[0] [receive] via NET/Libfabric/0/GDRDMA
NCCL INFO Channel 00/0 : 0[0] -> 8[0] [send]    via NET/Libfabric/0/GDRDMA
NCCL INFO Channel 08/0 : 0[0] -> 8[0] [send]    via NET/Libfabric/0/GDRDMA
NCCL INFO Connected all rings, use ring PXN 0 GDR 1
```

- `NET/Libfabric` = aws-ofi-nccl plugin selected
- `GDRDMA` = GPUDirect RDMA active (not bounce buffer)
- `GDR 1` = ring supports GPUDirect end-to-end

**330 GB/s busbw at 1 GiB** saturates ~80% of theoretical NVLink+EFA hybrid ring bandwidth on 2× H100 nodes. No TCP fallback.

## T12 — Dynamo disaggregated (PARTIAL)

Three DGDs applied:
- Frontend (CPU only, no GPU) — `Ready` in 75 s
- PrefillWorker (1 GPU, node 10.1.3.73) — loaded Llama-3.1-8B in 10.7 s from FSx cache
- DecodeWorker (1 GPU, node 10.1.3.30) — same

**Blockers surfaced:**

1. **`--connector nixl` deprecated** — current DGD YAML (`k8s/dgd-dynamo-combined-vllm.yaml`) predates the breaking Dynamo API change. Now requires:
   ```
   --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}'
   ```
   Patched inline in `t12-dgd-patched.yaml`.

2. **`RuntimeError: No plugins available for NIXL, cannot start transfers!`** — the pip-installed `nixl_cu12` wheel doesn't find its own plugins at default search paths. Plugins exist at:
   ```
   /opt/dynamo/venv/lib/python3.12/site-packages/.nixl_cu12.mesonpy.libs/plugins/libplugin_{UCX,LIBFABRIC,...}.so
   ```
   but NIXL's loader requires `NIXL_PLUGIN_DIR` env var to point there. Workaround applied (patched DGD envs); **Dockerfile should set this ENV by default** as a follow-up fix.

**What was proven:**
- Frontend routes requests to Prefill/Decode via etcd + NATS (operator shows `Ready`)
- Multi-node scheduling works (prefill on one node, decode on another)
- vLLM loads Llama-3.1-8B in bf16 with `kv_cache_dtype=auto`, `max_seq_len=4096` in under 11 s (FSx weight cache hits)
- Dynamo runtime is `v0.16.0` / `nixl-cu12 1.0.1` / NCCL `(2, 27, 5)` (torch bundled) — not the source-built 2.30.3

**What was not yet proven:**
- `/v1/completions` end-to-end through Frontend → Prefill → Decode
- Observed KV-cache transfer over NIXL between prefill and decode nodes
- Measured prefill/decode latency split

## Follow-up actions (in priority order)

1. **`Dockerfile.dynamo-combined-efa`** — add:
   ```
   ENV NIXL_PLUGIN_DIR=/opt/dynamo/venv/lib/python3.12/site-packages/.nixl_cu12.mesonpy.libs/plugins
   ENV LD_LIBRARY_PATH=/opt/dynamo/venv/lib/python3.12/site-packages/.nixl_cu12.mesonpy.libs:$LD_LIBRARY_PATH
   ```
   That's the fix for the NIXL plugin discovery failure. One commit, trigger CodeBuild, rerun T12.

2. **`k8s/dgd-dynamo-combined-vllm.yaml`** — update `--connector nixl` → `--kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}'` on prefill + decode.

3. **Add `docs/evidence/multinode-2026-05-05/t12-dgd-patched.yaml` as the canonical example** so customers don't hit the same two traps.

4. Consider shipping `nccl-tests/bin/all_reduce_perf` in the combined image (today only the `efa` base has it; combined drops it). Would make T11-style benches trivially runnable.

## Constraints honored

- **H100 only** (p5.48xlarge); P5en H200 never touched.
- `~/.claude/cluster-lock-h100.json` held as `multinode-d35812db45d6` throughout; released on completion.
- `nvshmem-efa/deepep-nvshmem` scaled 2→0 for the run, restored to 2 after.
- Pod anti-affinity ensured the two NCCL pods landed on different nodes.
- `NCCL_NVLS_ENABLE=0` in pod env to prevent NVLS init failure.

## Files

| File | Purpose |
|---|---|
| `t11-torch-allreduce.py` | the harness, 16-rank sweep 1 MiB–1 GiB |
| `t11-results.json` | machine-readable bandwidth sweep |
| `t11-rank0-full.log` | full NCCL_DEBUG=INFO from rank 0 |
| `t11-efa-proof.txt` | the GDRDMA / Libfabric / PXN / GDR lines |
| `t11-pods.txt` | pod placement on the two H100 nodes |
| `t12-dgd-patched.yaml` | the DGD YAML as applied (image + HF token + kv-transfer-config + NIXL_PLUGIN_DIR) |
| `t12-prefill-full.log` | prefill worker full log through NIXL plugin failure |
| `t12-pods.txt` | final DGD pod state |
| `t12-dgds.txt` | final DGD Ready state |
