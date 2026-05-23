# rev8 — PR #72 Dynamo + NIXL E2E on H100 (2026-05-21)

**Final verdict: ✅ PASS once `kv_connector_extra_config.backends=["LIBFABRIC"]` is added — but PR #72 currently SHIPS WITHOUT IT.**

## Setup
- Source: `dmvevents/awsome-inference-1` @ `feature/dynamo-combined-vllm-trtllm-efa` HEAD `d22f420`
- Manifest: `2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml`
- Image: `${ECR_REGISTRY}/dynamo-efa:9467d1460c71` (Dynamo 1.1.0 + NIXL v1.0.1)
- Cluster: 2× ml.p5.48xlarge HyperPod (`hyperpod-i-0a3eb6d3953cceaa7` + `hyperpod-i-0be4f4fecf22a73b3`)

## Two rounds

### Round 1 — PR #72 manifest as-is + nodeSelector ml.p5.48xlarge + hf-token secret patch
- ❌ HTTP 500 in 503 ms
- Decode worker EngineCore crashed: `nixl_cu12._bindings.nixlBackendError: NIXL_ERR_BACKEND` from `loadRemoteMD()` at `nixl_connector.py:1900`
- restartCount → 1
- Wire delta: 0 across all 24 NICs
- Visible Frontend symptom: `Failed to fold completions stream … invalid type: unit variant` (Dynamo 1.1.0 known masking bug — memory entry 19986)

### Round 2 — same setup + one-line kv_connector_extra_config fix
Applied to `--kv-transfer-config`:
```diff
-'{"kv_connector":"NixlConnector","kv_role":"kv_both"}'
+'{"kv_connector":"NixlConnector","kv_role":"kv_both","kv_connector_extra_config":{"backends":["LIBFABRIC"]}}'
```

- ✅ HTTP 200 in 1.85 s
- Real Llama-3.1-8B output: `" Paris. The capital of France is Paris. The capital of France is Paris. The capital of France"` (`finish_reason: length`, 20 completion_tokens)
- Decode worker log: `Backend LIBFABRIC was instantiated`
- Wire delta: **2,097,152 bytes `rdma_read_bytes`** (decode→prefill, exactly 2 MiB across 4 NICs on the prefill node — KV pull via NIXL libfabric)

## Wire-level finding
NIXL libfabric uses **RDMA READ** (`rdma_read_bytes`), not RDMA WRITE. The original gauge in upstream issue `nixl#1656` was looking for `rdma_write_bytes`; on this code path it stays at 0 even on a passing run. `rdma_read_bytes` is the right counter.

| NIC | Side | Δ tx_bytes | Δ rdma_read_bytes |
|---|---|---|---|
| 0a3e... rdmap79–82 | decode (sender of RDMA_READ requests) | 524,328 ea | 0 |
| 0be4... rdmap79–82 | prefill (target — bytes pulled by remote) | ~150 ea | 524,288 ea |
| **Total** | | **2,097,312 B** | **2,097,152 B** |

## ROOT CAUSE FOR REVIEWERS (CRITICAL)

`feature/dynamo-combined-vllm-trtllm-efa` HEAD `d22f420` does **NOT** include the rev7 fix that its own evidence directory claims validates the system.

Inspection of commit `4c43f0f rev7 — T12 FULL PASS`:
- Commit message describes the JSON one-liner fix in detail
- `git show --stat 4c43f0f` reveals: 1,817 insertions across 15 files — **all under `docs/evidence/multinode-2026-05-06-rev7/` and `docs/T12-HYPOTHESES-AND-FINDINGS.md`**
- **Zero code changes.** The DGD YAML was never modified.

The rev7 fix was almost certainly applied in-cluster via `kubectl edit dgd …`, the resulting passing run was captured as evidence, but the source manifest was not updated in git. Subsequent commits (`19a2aed` → `d22f420`) only touched build/EFA/NCCL plumbing, so the file at HEAD remains identical to `81327dd rev6`.

**Net effect:** anyone running `kubectl apply -f 2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml` from this branch hits Round 1 (NIXL_ERR_BACKEND), not Round 2 (HTTP 200).

## Mutations applied during this run
1. **Required for any cross-node test:** added `nodeSelector: node.kubernetes.io/instance-type: ml.p5.48xlarge` to PrefillWorker + DecodeWorker. Without it, anti-affinity placed PrefillWorker on a P4d (no native RDMA WRITE per cuco I250).
2. **Required for Frontend HF download:** patched cluster `hf-token` secret to add `HF_TOKEN` and `HUGGING_FACE_HUB_TOKEN` keys. Existing `token` keyname is not picked up by Frontend's HF SDK; workers pass via `/shared/hf_cache` cache hit, but Frontend reaching out for `USE_POLICY.md` got HTTP 401.
3. **Round 2 only:** the `kv_connector_extra_config` JSON edit (the missing rev7 fix).

All three are real fixes that PR #72 needs to ship.

## Files
- `01-apply.log`, `02-wait-ready.log` — Round 1 deploy
- `03-models.json` — Round 1 (model not registered, HF 401)
- `04-completion.json`, `04-curl-meta.txt` — Round 1 HTTP 500
- `05-decode-crash.log` — Round 1 NIXL_ERR_BACKEND traceback
- `06-prefill.log`, `07-frontend.log` — Round 1 worker logs
- `08-pods.txt`, `09-dgd-as-deployed.yaml` — Round 1 deployment record
- `counters-pre.txt`, `counters-post.txt` — Round 1 counters (zero delta)
- `round2-libfabric-forced/` — Round 2 evidence
  - `01-delete.log`, `02-apply.log`, `03-wait.log` — redeploy
  - `04-models.json` — model registered
  - `05-completion.json`, `05-curl-meta.txt` — **HTTP 200 + real Llama tokens**
  - `counters-r2-pre.txt`, `counters-r2-post.txt` — non-zero delta on rdma_read_bytes
- `source-commit.txt` — PR fork HEAD pin
