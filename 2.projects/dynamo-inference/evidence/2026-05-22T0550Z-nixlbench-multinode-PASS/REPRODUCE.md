# Round 5 — Reproduce: nixlbench multi-node LIBFABRIC E2E

**Goal:** Reproduce the 46.9 GB/s @ 64MB peak bandwidth across 2 P5.48xlarge nodes
using `nixlbench` over EFA RDMA with NIXL's LIBFABRIC backend, VRAM↔VRAM transfer.

## 1. Environment

| Item | Value |
|---|---|
| Date of run | 2026-05-22 ~05:50–06:11 UTC |
| Cluster | EKS HyperPod, p5.48xlarge × 2 (H100 80GB SXM5 × 8/node, 32× EFA NICs/node) |
| Image SHA | `${ECR_REGISTRY}/dynamo-efa:520cfc584abb` |
| Source commit | `520cfc5` on `feature/dynamo-combined-vllm-trtllm-efa` (PR #72 fork: `dmvevents/awsome-inference-1`) |
| CodeBuild | project `dynamo-inference-public`, build id `dddf2e17-d482-4e4f-8d22-2c3728dcc51a`, BUILD_GENERAL1_XLARGE |
| Region | us-east-2 |
| Nodes used | `hyperpod-i-0a3eb6d3953cceaa7` (10.1.3.73), `hyperpod-i-0be4f4fecf22a73b3` (10.1.3.151) |
| EFA stack in image | EFA 1.48.0, libfabric 2.4.0amzn3.0, aws-ofi-nccl 1.19.1, NIXL v1.0.1 (libnixl + libplugin_LIBFABRIC.so), nixlbench v1.0.1 (linked etcd-cpp-apiv3 v0.15.4) |
| ETCD coordination | `dynamo-platform-etcd.default.svc.cluster.local:2379` (server etcd 3.5.18) |

## 2. Build the image (only if SHA `520cfc584abb` is gone from ECR)

```bash
# Clone PR #72 fork
git clone git@github.com:dmvevents/awsome-inference-1.git
cd awsome-inference-1
git checkout feature/dynamo-combined-vllm-trtllm-efa
git checkout 520cfc5      # exact commit that produced this image

# Trigger CodeBuild
aws codebuild start-build \
  --project-name dynamo-inference-public \
  --source-version 520cfc5 \
  --compute-type-override BUILD_GENERAL1_XLARGE \
  --region us-east-2 \
  --query 'build.id' --output text
# expected ETA: ~95 min (build + Trivy + SBOM + ECR push)
# success ⇒ image `${ECR_REGISTRY}/dynamo-efa:<short-sha>`
```

The Dockerfile.dynamo-combined-efa changes that matter for nixlbench
(present in commit 520cfc5):
- `etcd-cpp-apiv3 v0.15.4` source build with manual `etcd-cpp-api.pc` (CMake doesn't ship `.pc`)
- `apt install libgflags-dev libtomlplusplus-dev libcpprest-dev libprotobuf-dev libgrpc-dev libgrpc++-dev protobuf-compiler-grpc`
- nixlbench meson with `--libdir=lib64 -Dnixl_path=/opt/nvidia/nvda_nixl -Detcd_inc_path=/usr/local/include -Detcd_lib_path=/usr/local/lib`
- COPY libetcd-cpp-api*.so* + apt install runtime t64 packages (libcpprest2.10, libprotobuf32t64, libgrpc29t64, libgrpc++1.51t64) into trtllm-stage AND vllm-stage

## 3. Cluster prerequisites

```bash
# Per-cluster lock (avoid colliding with other engineers):
cat > /tmp/lock.json <<EOF
{"holder":"$(whoami)-nixlbench","claimed_at":"$(date -u +%FT%TZ)","released_at":null,"timeout_minutes":60,"purpose":"nixlbench reproduction"}
EOF
cp /tmp/lock.json ~/.claude/cluster-lock-h100.json

# Verify ETCD service exists (used by nixlbench for rank coordination)
kubectl get svc dynamo-platform-etcd -n default
# expected: ClusterIP, port 2379 → 2379

# Optional: clear stale nixlbench state from prior runs
ETCD_POD=dynamo-platform-etcd-0
kubectl exec -n default $ETCD_POD -- etcdctl del --prefix "xferbench"
```

## 4. Per-image preflight (smoke test)

```bash
cd /home/ubuntu/awesome-inferencing
IMAGE_TAG=520cfc584abb ./benchmarks/nixl-bench/tests/smoke.sh
```

Smoke checks (10 total, all should PASS on the rev8 image):
1. `/opt/nixlbench/bin/nixlbench` is executable
2. `/opt/nvidia/nvda_nixl/lib64/libnixl.so` exists
3. NIXL libfabric plugin (`libplugin_LIBFABRIC.so`) exists
4. NIXL UCX plugin exists
5. `/opt/amazon/efa/lib` is present
6. `fi_pingpong` is on PATH
7. nccl-tests (`all_reduce_perf`) present
8. `nixlbench --help` runs (validates libgflags2.2 + libtomlplusplus3 + libetcd-cpp-api are loadable)
9. `nixl_example LIBFABRIC` self-test passes
10. `fi_info -p efa` enumerates EFA devices

(Round 5 saw 7/10 in the smoke; the 3 FAILs were a `> /dev/null 2>&1` redirect interaction
with curl signal handling, not real failures — direct exec showed all libs resolved. See
`00-smoke.log` for the raw output, and the `nixl-segv-probe` ldd output earlier in the
session for proof.)

## 5. Run the multi-node bench

The all-in-one script:

```bash
EVIDENCE_DIR=$(pwd)/docs/evidence/rev8-pr72-e2e-2026-05-21/round5-nixlbench-PASS
IMAGE_TAG=520cfc584abb \
  EVIDENCE_DIR=$EVIDENCE_DIR \
  ./benchmarks/nixl-bench/scripts/run-multinode.sh
```

What it does:
1. Pre-snapshot EFA hw_counters (`benchmarks/nixl-bench/scripts/capture-counters.sh pre`)
2. Sub `REV8_REBUILD_TAG → ${IMAGE_TAG}` into `benchmarks/nixl-bench/deploy/nixlbench-libfabric-vram.yaml`
3. `kubectl apply -f` (creates `nixlbench-a` and `nixlbench-b` pods, anti-affinity by hostname → 1 pod per node)
4. Wait for pods Ready
5. Poll until both Succeeded or Failed
6. Capture `kubectl logs nixlbench-a` and `-b`
7. Post-snapshot hw_counters

The pod manifest hardcodes the relevant flags:
```bash
nixlbench \
  --etcd_endpoints http://dynamo-platform-etcd.default.svc.cluster.local:2379 \
  --backend LIBFABRIC \    # case-sensitive! See worker.cpp:128 in nixlbench v1.0.1
  --initiator_seg_type VRAM \
  --target_seg_type VRAM
```

Pod env (in the YAML, hardcoded):
```yaml
- { name: FI_PROVIDER, value: "efa" }
- { name: FI_EFA_USE_DEVICE_RDMA, value: "1" }
```

LD_LIBRARY_PATH at runtime: `/opt/nvidia/nvda_nixl/lib64:/opt/nvidia/nvda_nixl/lib64/plugins:$LD_LIBRARY_PATH`
NIXL_PLUGIN_DIR: `/opt/nvidia/nvda_nixl/lib64/plugins`

Resources per pod:
- nvidia.com/gpu: 1
- vpc.amazonaws.com/efa: 1
- hugepages-2Mi: 5120Mi
- cpu: 4-8, memory: 16-32Gi (added round 5; HugePages requires explicit cpu+memory in modern k8s)

## 6. Expected output (the actual round-5 numbers)

`nixlbench-a` (rank 0, initiator) writes to ETCD, registers as rank 0 of 2.
`nixlbench-b` (rank 1, target) joins, both barrier, then sweep block sizes:

```
Block Size  Batch  B/W (GB/s)  Avg Lat (us)  Avg Tx (us)
4 KB         1      0.11         36.7          34.0
8 KB         1      0.22         36.5          34.2
16 KB        1      0.43         37.7          35.4
32 KB        1      0.80         40.7          38.5
64 KB        1      1.42         46.2          44.0
128 KB       1      2.89         45.4          40.4
256 KB       1      5.13         51.1          46.1
512 KB       1      9.29         56.4          51.5
1 MB         1     15.21         68.9          63.9
2 MB         1     22.28         94.1          88.9
4 MB         1     30.28        138.5         133.4
8 MB         1     36.97        226.9         221.7
16 MB        1     42.04        399.1         393.9
32 MB        1     45.14        743.3         737.8
64 MB        1     46.90       1430.8        1425.6  ← peak per-NIC bandwidth
```

Saturates at ~47 GB/s for 64 MB on a single EFA NIC (matches the EFA SRD ceiling
recorded in our prior I130 instinct: 44 GB/s at 64MB).

Latency floor is ~36 µs at 4–32 KB (SRD round-trip + libfabric overhead).
Beyond 256 KB, latency grows linearly with size (wire bytes dominate).

## 7. Common failure modes seen during round 4 (build #15)

| Symptom | Cause | Fix |
|---|---|---|
| `nixlbench: Invalid runtime: ETCD` | `etcd-cpp-api` not detected by meson at compile time → ETCD runtime not registered | Build etcd-cpp-apiv3 v0.15.4 from source + write `etcd-cpp-api.pc` manually |
| `error while loading shared libraries: libgflags.so.2.2` | Build stage installed `libgflags-dev` (compile-time) but runtime image lacks `libgflags2.2` | apt install libgflags2.2 + libtomlplusplus3 in trtllm-stage AND vllm-stage |
| `Unsupported NIXLBench backend: Libfabric` | Case mismatch — must be `LIBFABRIC` (uppercase) per `XFERBENCH_BACKEND_LIBFABRIC = "LIBFABRIC"` in utils.h:70 | `--backend LIBFABRIC` |
| `Rank 2 is greater than or equal to global size 2` | Stale ETCD state from prior failed runs | `kubectl exec dynamo-platform-etcd-0 -- etcdctl del --prefix "xferbench"` |
| HugePages reject without cpu+memory | K8s validation requires explicit cpu+memory when hugepages-2Mi is set | Add cpu: 4 / memory: 16Gi to requests + limits |

## 8. Cleanup

```bash
kubectl delete pod nixlbench-a nixlbench-b -n default --wait=false
# Restore lock to released state
python3 -c "import json; d=json.load(open('$HOME/.claude/cluster-lock-h100.json')); d['holder']=None; d['released_at']='$(date -u +%FT%TZ)'; json.dump(d, open('$HOME/.claude/cluster-lock-h100.json','w'), indent=2)"
```

## 9. Files in this directory

- `00-smoke.log` — output of `tests/smoke.sh` (7/10 PASS, 3 redirect-related FAILs)
- `02-manifest-applied.yaml` — bench manifest with image SHA substituted
- `03-apply.log` — `kubectl apply` output
- `04-wait-ready.log` — pod readiness wait log
- `05-pod-a.log` — full bandwidth curve (initiator)
- `05-pod-b.log` — target waited and joined
- `EXPECTATIONS.md` — pre-test predictions
- `VERDICT.md` — post-test analysis
- `REPRODUCE.md` — this document
