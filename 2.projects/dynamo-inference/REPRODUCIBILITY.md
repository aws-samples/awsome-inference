# Reproducibility

How to reproduce any evidence committed under `docs/evidence/`
without needing access to the private ECR account (058264135704)
referenced in the logs.

The committed evidence is a forensic record — it quotes the exact
image URIs as they existed in our build account. External readers
and upstream maintainers reproduce from **source** using this doc.

---

## 1. What you need

- Docker 24+ (BuildKit), ~60 GB free disk, ~120 GB peak during build
- AWS account with EC2 `p5.48xlarge` (8× H100) quota for multi-node tests
  (Objective 3 below is the only lane that needs GPUs; the build itself
  runs on any x86_64 Linux host)
- `kubectl` + an EKS or SageMaker HyperPod cluster for end-to-end tests
- HuggingFace access token for gated models (Llama-3.1 etc.)

No NVIDIA NGC credentials required. The Dockerfiles pull only
**public** NGC images (`nvcr.io/nvidia/cuda-dl-base`,
`nvcr.io/nvidia/ai-dynamo/{tensorrtllm,vllm}-runtime`).

---

## 2. Build the same image the evidence was produced on

Each evidence directory under `docs/evidence/` pins a `commit SHA` in
its README. To reproduce evidence dir `multinode-2026-05-06-rev5/`,
the image SHA is `9467d1460c71`:

```bash
git clone https://github.com/aws-samples/awsome-inference.git
cd awsome-inference
gh pr checkout 72     # or checkout the feature branch directly
git checkout 9467d14  # the exact commit the evidence was built from

cd 2.projects/dynamo-inference
./build.sh -b combined -t 9467d1460c71
# produces local image `dynamo-efa:9467d1460c71` (~25 GB, ~45 min cold build)
```

To reproduce earlier evidence:

| Evidence dir | Dockerfile commit | Image SHA |
|---|---|---|
| `post-rename-smoke-2026-05-05/` | `d35812d` | `d35812db45d6` |
| `multinode-2026-05-05-rev2/` | `81f61cc` | `a1725d43e5c0` |
| `multinode-2026-05-05-rev3/` | `b1f64c6` | `a1725d43e5c0` |
| `multinode-2026-05-06-rev4/` | `9592bdf` | `a1725d43e5c0` |
| `multinode-2026-05-06-rev5/` | `9467d14` | `9467d1460c71` |

Each SHA is the **git commit** that was built; the image tag
matches. No extra version pinning is needed — the Dockerfile's
base-image `ARG`s (`TRTLLM_IMAGE`, `VLLM_IMAGE`, `CUDA_DL_BASE`)
are pinned in the checked-out source.

---

## 3. Read the evidence with the right mental model

Log lines like:

```
image=058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-efa:9467d1460c71
```

refer to our build account's private ECR — **you won't have access,
and you don't need it.** The `:9467d1460c71` tag is a git SHA, and
any image built from that commit is behaviorally identical. For
external reproduction, substitute with the image you just built.

Similarly, logs reference:

- **Internal node names** like `hyperpod-i-01aee349f9991c414` —
  our HyperPod cluster nodes; swap for your own k8s node names
- **Private subnet IPs** like `10.1.3.30`, `10.1.3.73` — our pod IPs;
  yours will differ

Treat them as placeholders. The SHA and commit hash are the load-bearing
identifiers.

---

## 4. Reproduce specific gates

### Smoke T1–T10 (single pod, ~20 min)

```bash
cd 2.projects/dynamo-inference
export YOUR_ECR=<your-account>.dkr.ecr.<region>.amazonaws.com
docker tag dynamo-efa:9467d1460c71 ${YOUR_ECR}/dynamo-efa:9467d1460c71
aws ecr get-login-password | docker login --username AWS --password-stdin ${YOUR_ECR}
docker push ${YOUR_ECR}/dynamo-efa:9467d1460c71

# Edit tests/smoke/smoke-pod.yaml — change `image:` to your ECR URI
kubectl apply -f tests/smoke/smoke-pod.yaml
./tests/smoke/smoke.sh 9467d1460c71
```

Expected: 10/10 gates PASS. See any of the rev2+ evidence READMEs for
the gate rubric.

### T11 cross-node NCCL AllReduce (2× H100, ~15 min)

```bash
# Edit tests/multinode/nccl-allreduce.yaml — change `image:` to your ECR URI
kubectl apply -f tests/multinode/nccl-allreduce.yaml
# Wait for both pods Ready
# Launch 16-rank harness (per-pod, 8 ranks each) — see
#   docs/evidence/multinode-2026-05-06-rev5/t11-torch-allreduce.py
```

Expected: ~330 GB/s busbw at 1 GiB on 2× p5.48xlarge. NCCL logs should
show `NET/Libfabric/0/GDRDMA` (not TCP).

### T12 disaggregated Llama-3.1-8B (2× H100, ~25 min)

```bash
# Edit k8s/dgd-dynamo-combined-vllm.yaml — change image:, PVC name, HF secret ref
kubectl apply -f k8s/dgd-dynamo-combined-vllm.yaml
kubectl port-forward svc/dynamo-combined-vllm-frontend 8000:8000 &
curl -X POST http://localhost:8000/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"Hello,","max_tokens":32,"temperature":0}'
```

**Known issue:** on Dynamo 1.0.1 + 1.1.0 operator, `/v1/models` returns
`{"data":[]}` and `/v1/completions` returns 404. Frontend's
`KubeDiscoveryClient` returns `0 instances for query=AllEndpoints` every
10 s despite correct namespace registration by workers. Filed upstream
as [ai-dynamo/dynamo#9200](https://github.com/ai-dynamo/dynamo/issues/9200).

The image side passes every other gate; T12 unblocks when the upstream
operator fix lands. No rebuild required.

---

## 5. What commits changed what

| Commit | Change |
|---|---|
| `81f61cc` | Single-image A100→B300 support (sm_80/86/89/90/100/120 NCCL fat-binary), `--base-image` CodeBuild arg |
| `d35812d` | On-cluster smoke harness (10 gates) |
| `ce21673` | NIXL plugin discovery (`NIXL_PLUGIN_DIR` to pip wheel path) + Dynamo 0.16 `--kv-transfer-config` migration |
| `a1725d4` | nccl-tests source build in combined image |
| `b1f64c6` | Merge 3 separate DGDs → 1 canonical DGD (upstream `disagg.yaml` pattern) |
| `9592bdf` | `DYN_NAMESPACE_WORKER_SUFFIX=""` override attempt |
| `b2f1c78` | Dynamo 1.0.1 → 1.1.0 runtime bump |
| `9467d14` | OKRs 2026-05-06 |

---

## 6. If reproduction diverges

If your build or validation differs from the committed evidence:

1. **Check the commit SHA matches.** `git rev-parse HEAD` inside
   `awsome-inference` should equal the SHA listed in the evidence dir's
   README.
2. **Check Dockerfile base-image ARGs.** `TRTLLM_IMAGE`, `VLLM_IMAGE`,
   `CUDA_DL_BASE` should match the comments in
   `Dockerfile.dynamo-combined-efa`.
3. **Check EFA stack version.** The committed evidence uses EFA 1.48.0,
   libfabric 2.4.0amzn3.0, NCCL 2.30.3, UCX v1.20.0. Newer versions
   may behave differently.
4. **If the discrepancy is in T12 behavior on Dynamo 1.1.0,** the most
   likely cause is upstream #9200 — file a subscription comment, don't
   debug from scratch.

---

## 7. File a reproducibility issue

If you cannot reproduce despite matching commit + base images, open a
GitHub issue on [aws-samples/awsome-inference](https://github.com/aws-samples/awsome-inference/issues)
with:

- Exact `git rev-parse HEAD` of your checkout
- Output of `docker buildx build --check -f Dockerfile.dynamo-combined-efa .`
- First 200 lines of the CodeBuild / local build log
- Kubernetes version + operator versions (`kubectl get crd | grep dynamo`)
- Hardware (instance type, driver version, `nvidia-smi`)
