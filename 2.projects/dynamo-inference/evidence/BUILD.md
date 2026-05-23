# Building the rev8 image hierarchy (`efa:520cfc584abb` → `dynamo-efa:520cfc584abb`)

This document captures the exact builds that produced the canonical
campaign images. The Dockerfile + build.sh + buildspec.yml are
snapshotted in `build-snapshot/` at the exact commit `520cfc5`.

## The 2-image hierarchy

| Image | FROM | Built by | Purpose | Digest (canonical pin) |
|---|---|---|---|---|
| **`efa`** (networking base) | `nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04` (public NGC) | `Dockerfile.efa` | EFA + GDRCopy + UCX + NIXL + NCCL + nccl-tests + nixlbench | `sha256:6641dfa1e5cd5335cef541accd1299348be730f00d5b4371b288ed0557bd3d50` |
| **`dynamo-efa`** (combined) | `nvcr.io/nvidia/ai-dynamo/{tensorrtllm,vllm}-runtime:1.1.0` (public NGC) + `--base-image efa:<sha>` | `Dockerfile.dynamo-combined-efa` | TRT-LLM + vLLM stages overlayed with networking from `efa` | `sha256:48e6e3104b523bc1828deda9966c48260de06bb8649348930f5440cad7f83d9c` |

Both images are tagged with the same `<sha>` (the source commit SHA).
The `dynamo-efa` image is what's deployed; the `efa` image is its
networking-stack ancestor and is reused via `--base-image` to skip
~25 minutes of rebuild on subsequent dynamo-efa builds.

## Build chain

```
nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04   (public NGC)
         │
         ▼ Dockerfile.efa
   efa:520cfc584abb                                            (digest: 6641dfa1...)
         │
         ▼ Dockerfile.dynamo-combined-efa  --base-image efa:520cfc584abb
   dynamo-efa:520cfc584abb                                     (digest: 48e6e310...)
         │
         ▼ kubectl apply (DGD)
   Frontend + PrefillWorker + DecodeWorker pods
```

## Option A — pull the existing images

If the images are still in ECR (they are, as of campaign date):

```bash
# Networking base
docker pull ${ECR_REGISTRY}/efa:520cfc584abb
# Combined (deployed image)
docker pull ${ECR_REGISTRY}/dynamo-efa:520cfc584abb
```

Image digests (verify after pull with `docker manifest inspect`):

| Image | Digest |
|---|---|
| `efa:520cfc584abb` | `sha256:6641dfa1e5cd5335cef541accd1299348be730f00d5b4371b288ed0557bd3d50` |
| `dynamo-efa:520cfc584abb` | `sha256:48e6e3104b523bc1828deda9966c48260de06bb8649348930f5440cad7f83d9c` |

If you don't have access to the campaign's ECR, mirror to your own ECR
and update DGD manifests to point there. The image works in any region
that supports p5.48xlarge.

## Option B — rebuild from source

### 1. Clone the PR fork at the exact commit

```bash
git clone git@github.com:dmvevents/awsome-inference-1.git
cd awsome-inference-1
git checkout 520cfc5
```

If `dmvevents/awsome-inference-1` is unavailable, use the snapshot in
`build-snapshot/` (the four files there are byte-identical to commit
`520cfc5`):

```bash
mkdir -p /tmp/build && cd /tmp/build
cp <campaign-dir>/build-snapshot/Dockerfile.dynamo-combined-efa Dockerfile.dynamo-combined-efa
cp <campaign-dir>/build-snapshot/Dockerfile.efa Dockerfile.efa
cp <campaign-dir>/build-snapshot/buildspec.yml buildspec.yml
cp <campaign-dir>/build-snapshot/build.sh build.sh
chmod +x build.sh
```

### 2. Trigger AWS CodeBuild (the canonical path)

```bash
aws codebuild start-build \
  --project-name dynamo-inference-public \
  --source-version 520cfc5 \
  --compute-type-override BUILD_GENERAL1_XLARGE \
  --region us-east-2 \
  --query 'build.id' --output text
# expected ETA: ~95 min (build + Trivy CVE scan + SBOM + ECR push)
# success ⇒ image at $ECR/dynamo-efa:<short-sha>
```

The CodeBuild project `dynamo-inference-public` runs `buildspec.yml`,
which calls `./build.sh -b combined -t <sha>`. The build does:

1. `Dockerfile.efa`: stage 1 = efa-rdma-stage (cuda-dl-base + EFA + GDRCopy);
   stage 2 = networking-builder (UCX + NIXL + NCCL); stage 3 = networking-runtime
2. `Dockerfile.dynamo-combined-efa`: rebuilds same stages from scratch (no
   cross-Dockerfile reuse — see `dockerfile-multi-stage-copy-audit` skill).
   Then trtllm-stage (FROM nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.1.0)
   and vllm-stage (FROM nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.1.0) overlay
   on top with COPY --from=networking
3. Combined stage = vllm-stage + TRT-LLM venv overlay
4. Trivy CVE scan → `/opt/security/cve-report.txt`
5. Syft SBOM → `/opt/security/sbom.spdx.json`
6. ECR push to two tags: `dynamo-efa:<short-sha>` and `dynamo-efa:latest`

### 3. Watch the build

```bash
BUILD_ID=<from-step-2>
while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region us-east-2 \
    --query 'builds[0].buildStatus' --output text)
  PHASE=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region us-east-2 \
    --query 'builds[0].currentPhase' --output text)
  echo "$(date -u +%H:%M:%SZ) phase=$PHASE status=$STATUS"
  [ "$STATUS" != "IN_PROGRESS" ] && break
  sleep 60
done
```

Expected phase progression: `SUBMITTED → QUEUED → PROVISIONING → DOWNLOAD_SOURCE → INSTALL → PRE_BUILD → BUILD → POST_BUILD → COMPLETED`. Total ~95 min on BUILD_GENERAL1_XLARGE.

### 4. Local-machine alternative (NOT the canonical path, kept for completeness)

```bash
cd /tmp/build
DOCKER_BUILDKIT=1 ./build.sh -b efa -t local-rev8 --no-extract
DOCKER_BUILDKIT=1 ./build.sh -b combined -t local-rev8 --no-extract --base-image "efa:local-rev8"
docker tag combined:local-rev8 your-registry/dynamo-efa:local-rev8
docker push your-registry/dynamo-efa:local-rev8
```

Local builds need ≥80GB free disk + 32GB RAM + GPU access for the build
machine. Slower (~2 hours) and skips the CVE scan. Not recommended unless
CodeBuild is unavailable.

## Verifying the build produced the right image

After the build completes:

```bash
# 1. Image SHA
docker manifest inspect <ECR>/dynamo-efa:<tag> | jq -r '.config.digest'
# expected: sha256:48e6e3104b... (if you rebuilt from commit 520cfc5)

# 2. nixlbench works (the round-5 deal-breaker)
docker run --rm --gpus all <ECR>/dynamo-efa:<tag> /opt/nixlbench/bin/nixlbench --help
# expected: prints flag list, exit 0

# 3. /opt/nvidia/nvda_nixl/lib64/plugins/libplugin_LIBFABRIC.so exists
docker run --rm <ECR>/dynamo-efa:<tag> ls /opt/nvidia/nvda_nixl/lib64/plugins/
# expected: libplugin_LIBFABRIC.so + libplugin_UCX.so

# 4. vLLM + Dynamo CLI present
docker run --rm <ECR>/dynamo-efa:<tag> /opt/dynamo/venv/bin/python3 -c \
  "import dynamo.frontend; import dynamo.vllm; print('OK')"
# expected: OK
```

If step 2 fails with `libgflags.so.2.2: cannot open shared object file`
or `Invalid runtime: ETCD`, the build did NOT include the runtime libs
or etcd-cpp-apiv3 source build. Re-check that you're at commit `520cfc5`
or later.

## What the build produces

| Output | Path in image | Size |
|---|---|---|
| nixlbench binary | `/opt/nixlbench/bin/nixlbench` | ~6 MB |
| NIXL libfabric plugin | `/opt/nvidia/nvda_nixl/lib64/plugins/libplugin_LIBFABRIC.so` | ~2 MB |
| NIXL UCX plugin | `/opt/nvidia/nvda_nixl/lib64/plugins/libplugin_UCX.so` | ~2 MB |
| nccl-tests | `/opt/nccl-tests/bin/all_reduce_perf` etc. | ~50 MB |
| EFA stack | `/opt/amazon/efa/`, `/lib/x86_64-linux-gnu/libefa.so*` | ~10 MB |
| Dynamo + vLLM | `/opt/dynamo/venv/` | ~6 GB |
| TRT-LLM | `/opt/dynamo/venv/lib/python3.12/site-packages/tensorrt_llm/` | ~12 GB |
| CVE report | `/opt/security/cve-report.txt` | ~1 KB |
| SBOM | `/opt/security/sbom.spdx.json` | ~10 MB |

Total compressed image: ~26 GB. Pull time on a P5 node: ~2-3 min.
