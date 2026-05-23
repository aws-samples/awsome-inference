# Dynamo + NIXL + EFA — what works, what's broken, what to fix (2026-05-21 rev8)

## TL;DR

This subproject builds three artifacts:

| Artifact | What | Source of truth |
|---|---|---|
| **`efa:gpu`** (a.k.a. `public.ecr.aws/hpc-cloud/efa:gpu`) | EFA + UCX + NIXL + NCCL networking base | `Dockerfile.efa` |
| **`dynamo-efa:<sha>`** | Dynamo 1.1.0 + vLLM 0.19 + TRT-LLM, layered over `efa:gpu` | `Dockerfile.dynamo-combined-efa` |
| **DGD manifest** | DynamoGraphDeployment K8s YAML (Frontend + Prefill + Decode) | `k8s/dgd-dynamo-combined-vllm.yaml` |

**Critical:** the manifest's `--kv-transfer-config` MUST include `kv_connector_extra_config:{backends:["LIBFABRIC"]}`. Without it, NIXL falls back to UCX which cannot complete the handshake on EFA's RDM endpoint type. This was discovered in rev7 (commit `4c43f0f`) but the fix was applied via `kubectl edit` and not committed back to the manifest until rev8 (commit `47c2f2c`).

## What works (verified live on H100 P5.48xlarge cross-node 2026-05-21)

| Layer | Test | Result |
|---|---|---|
| L1 | `fi_pingpong -p efa` cross-node | ✅ 213 MB/s |
| L1 | `mpijob-nccl-allreduce-g5.yaml` | ✅ (NCCL collective on g5) |
| L2 | `nixl_example LIBFABRIC` (NIXL official self-test) | ✅ |
| L2 | NIXL Python API cross-node (via Dynamo prefill→decode) | ✅ |
| L3 | `/v1/completions` (Llama-3.1-8B disagg) | ✅ HTTP 200 in 1.85s |
| L3 wire | `rdma_read_bytes` delta during one request | ✅ exactly 2 MiB across 4 NICs |

## Known failures (and the fix in each case)

### 1. Default `--kv-transfer-config` selects UCX → handshake fails on EFA

**Symptom:** Decode worker raises `nixl_cu12._bindings.nixlBackendError: NIXL_ERR_BACKEND` from `loadRemoteMD()`. Frontend returns HTTP 500 with `Failed to fold completions stream … invalid type: unit variant` (this is the secondary symptom — a known Dynamo 1.1.0 handlers.py bug that emits bare `finish_reason: "error"` and breaks the Rust enum deserializer).

**Fix (already applied, rev8 commit `47c2f2c`):** `--kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both","kv_connector_extra_config":{"backends":["LIBFABRIC"]}}'`

**Why no env-var fix:** vLLM `nixl_connector.py:1022-1024` hardcodes the default to `["UCX"]` and ignores `NIXL_BACKEND` / `VLLM_NIXL_KVCACHE_BACKEND` (filed as `vllm-project/vllm#41814`). Only the JSON `kv_connector_extra_config.backends` path is read.

### 2. PrefillWorker can land on a P4d (no native RDMA WRITE)

**Symptom:** Anti-affinity puts Prefill on a P4d.24xlarge node; `loadRemoteMD()` succeeds but cross-node KV transfer never produces RDMA bytes (P4d EFA has `max_qp_rd_atom=0`, cuco I250).

**Fix (already applied, rev8 commit `47c2f2c`):** `nodeSelector: node.kubernetes.io/instance-type: ml.p5.48xlarge` on both PrefillWorker and DecodeWorker. P5en works too — relax to a label-based selector if you want H200 support.

### 3. Workshop UCX page (`ucx_perftest`) fails on hostNetwork pods

**Symptom:** UCX picks the EC2 metadata link-local IP (`169.254.0.1`) for OOB rendezvous, gets `connect: Connection refused`, declares peer "unreachable".

**Fix (workshop docs need updating):** Set `UCX_NET_DEVICES=` to scope to actual EFA interfaces, or `UCX_TLS=rc,sm,self` to drop TCP entirely. Note: UCX is NOT the production transport on EFA — it's an educational comparison only. The page should make this explicit.

### 4. Workshop NIXL page defaults to UCX

**Symptom:** `/opt/nvidia/nvda_nixl/bin/nixl_example` (no args) selects UCX by default and fails the same way Dynamo did before rev7.

**Fix (workshop docs):** Always pass `LIBFABRIC` as the backend arg: `nixl_example LIBFABRIC`. PASS verified live.

### 5. `nixlbench` binary is silently missing from `efa:gpu`

**Symptom:** `Dockerfile.efa` has a `--- nixlbench ---` build stage at line ~191, but the resulting `/opt/nixlbench/bin/nixlbench` is NOT in the running image. The meson build fails silently because `pkg-config`, `libgflags-dev`, and `libetcd-cpp-api-dev` are missing at configure time.

**Fix (already applied, rev8 commit pending):** Added `apt-get install pkg-config libgflags-dev libetcd-cpp-api-dev` before the meson setup, plus a `test -x /opt/nixlbench/bin/nixlbench` post-build assertion so the build fails loudly instead of silently shipping a broken stage.

### 6. `hf-token` Secret keyname doesn't match Dynamo Frontend's HF SDK expectation

**Symptom:** Frontend hits HTTP 401 fetching `USE_POLICY.md` from HuggingFace because the Secret only exposes `token` (lowercase) via `envFromSecret`, not the `HF_TOKEN`/`HUGGING_FACE_HUB_TOKEN` keys the SDK reads.

**Fix (cluster-side patch, no manifest mutation):**
```bash
TOK=$(kubectl get secret hf-token -n default -o jsonpath='{.data.token}')
kubectl patch secret hf-token -n default --type=json -p="[
  {\"op\":\"add\",\"path\":\"/data/HF_TOKEN\",\"value\":\"$TOK\"},
  {\"op\":\"add\",\"path\":\"/data/HUGGING_FACE_HUB_TOKEN\",\"value\":\"$TOK\"}
]"
kubectl delete pod -l nvidia.com/dynamo-component=Frontend -n default  # force restart
```

## How to verify a deployment

After `kubectl apply -f k8s/dgd-dynamo-combined-vllm.yaml`:

1. `kubectl get dgd dynamo-combined-vllm` → READY=True (3/3 services)
2. `kubectl get pods -l nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm -o wide` → Prefill + Decode on **different P5 nodes**, Frontend anywhere
3. Decode pod log contains `Backend LIBFABRIC was instantiated` (NOT `Backend UCX`)
4. `curl -X POST http://localhost:8000/v1/completions -H 'Content-Type: application/json' -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"Hello","max_tokens":10,"stream":false}'` → HTTP 200 with non-empty `choices[0].text`
5. Compare hw_counter `rdma_read_bytes` across `/sys/class/infiniband/rdmap*/ports/1/hw_counters/` before vs after the request → delta > 1 MiB on the prefill node

If any of those fail, the fix is in `docs/evidence/rev8-pr72-e2e-2026-05-21/SUMMARY.md` (full 2-round trace) or `docs/evidence/rev8-pr72-e2e-2026-05-21/TEAM-FINDINGS.md` (workshop UCX/NIXL fixes).

## Hard rules for editing this subproject

- **Never default to UCX backend on EFA.** Every NIXL consumer (vLLM, nixl_example, nixlbench, workshop tests) must explicitly select `LIBFABRIC`. UCX cannot do EFA's RDM endpoint.
- **Never apply a fix in-cluster only.** If you `kubectl edit` a manifest and it works, commit the same edit back to the source YAML in this directory. The rev7 silent-rollback (commit `4c43f0f` advertised the fix as code but only added evidence docs) cost the team a re-debug cycle.
- **Worker pods must have a `readinessProbe`** on `/health:9090`. Without it, EndpointSlice stays Ready=False during model load and KubeDiscoveryClient (Dynamo 1.1.0 daemon.rs:246) returns 0 instances. See rev6 commit `81327dd` for the canonical probe spec.
- **Cross-node KV transfer must be P5↔P5 (or P5en↔P5en).** P4d has `max_qp_rd_atom=0` and cannot do native RDMA WRITE/READ; `loadRemoteMD()` may even succeed but counters won't move.
