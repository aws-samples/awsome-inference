# Tests

On-cluster verification for the `dynamo-efa` image. Runs after every CodeBuild
push to guarantee the image boots on H100, uses EFA RDMA (not TCP fallback),
and serves a chat completion.

## Layout

```
tests/
├── smoke/
│   ├── smoke.sh            # the harness (10 gates, T1–T10)
│   └── smoke-pod.yaml      # single-pod vLLM template (substituted at run time)
├── out/
│   └── <SHA>/              # per-run evidence (logs, JSON, counters, summary)
└── e2e-evidence/           # older multi-node evidence from PR #72
```

## Run

```
cd 2.projects/dynamo-inference
./tests/smoke/smoke.sh <SHA>                      # pulls ECR/dynamo-efa:<SHA>
./tests/smoke/smoke.sh <SHA> <IMAGE_URI>          # explicit URI override
```

Env overrides:

| Var                  | Default                    | Meaning |
|----------------------|----------------------------|---------|
| `MODEL`              | `facebook/opt-125m`        | tiny smoke model, no HF token required |
| `SMOKE_ALLOW_WARN`   | `0`                        | set `1` to promote T8–T10 warnings to pass |
| `K8S_NAMESPACE`      | `default`                  | |
| `AWS_REGION`         | `us-east-2`                | |
| `AWS_ACCOUNT_ID`     | `058264135704`             | |
| `ECR_REPO_PREFIX`    | empty                      | matches buildspec.yml |

## Criteria

Blocking (T1–T7) — any failure aborts the run and returns non-zero.
Warning (T8–T10) — fails the run by default, can be overridden with
`SMOKE_ALLOW_WARN=1` during triage.

| # | Layer | Pass criterion | Blocking? |
|---|---|---|---|
| T1 | **Image build** | `dynamo-efa:<SHA>` resolvable in ECR. CVE gate already passed in CodeBuild post-build. | yes |
| T2 | **Image sanity** | Image size < 52 GB. `nixl.version` / `nvshmem` / `cuda.version=12.9` labels present. | yes |
| T3 | **Fat-binary NCCL** | `strings libnccl.so.2.30.3` contains every one of: `sm_80`, `sm_86`, `sm_89`, `sm_90`, `sm_100`, `sm_120`. Confirms A100 → B300 + L40S coverage without JIT. | yes |
| T4 | **EFA visible in pod** | `fi_info -p efa` lists ≥1 device. `/dev/infiniband` mounted. Pod is on `ml.p5.48xlarge`. | yes |
| T5 | **Serving boots** | Pod reaches `Ready` in ≤ 10 min. `GET /v1/models` returns 200. | yes |
| T6 | **Chat completion** | `POST /v1/completions` with 64-token prompt returns 200 with non-empty `choices[0].text`. Latency recorded (no hard gate). | yes |
| T7 | **RDMA actually used** | After one serve cycle, any `/sys/class/infiniband/rdmap*/ports/1/hw_counters/*_bytes` counter is non-zero. If all-zero ⇒ TCP fallback detected, smoke **fails**. | yes |
| T8 | **No NCCL/NVLS errors** | Pod log contains no `Couldn't initialize NVLS` or `NCCL WARN` / `NCCL ERROR`. | warn |
| T9 | **SBOM present** | `/opt/security/sbom.spdx.json` + `sbom.cyclonedx.json` exist and parse as JSON. | warn |
| T10 | **Teardown clean** | Pod deletes within 60 s (trap); lock released. | warn |

## Environment constraints (hard rules)

Enforced by the harness:

- **H100 only.** `nodeSelector` pins pods to `node.kubernetes.io/instance-type=ml.p5.48xlarge`
  (`hyperpod-i-01aee349f9991c414` / `hyperpod-i-0a3eb6d3953cceaa7`). P5en H200 nodes are
  reserved for another engineer — never target them.
- **Cluster lock.** `~/.claude/cluster-lock-h100.json` is claimed at start, released on
  exit (`trap teardown EXIT`). If the lock is held by someone else, the harness aborts.
- **Pod-freshness preflight (I685).** Any stale `smoke-<SHA>` pod is deleted before deploy.
- **Single-pod scope.** This is a smoke test, not a multi-node training validation.
  For 2-node NIXL/KV-transfer evidence, see `tests/e2e-evidence/`.

## Evidence artifacts

Per run, `tests/out/<SHA>/` contains:

| File | Source |
|---|---|
| `smoke.log` | full harness output (tee'd) |
| `ecr-describe.json` | ECR image metadata (T1–T2) |
| `smoke-pod.rendered.yaml` | the manifest actually applied (post-substitution) |
| `pod-describe.txt` | `kubectl describe pod` at Ready time |
| `pod-logs.txt` | container logs (T8 source) |
| `fi_info.txt` | EFA device list (T4) |
| `nccl-arches.txt` | sm_* strings from libnccl.so (T3) |
| `v1-models.json` | `/v1/models` response (T5) |
| `completion.json` | `/v1/completions` response (T6) |
| `hw_counters.txt` | every `/sys/class/infiniband/rdmap*/hw_counters/*` (T7) |
| `sbom-check.txt` | SBOM file existence + JSON-parse result (T9) |
| `summary.md` | machine-readable run summary |

## CI wiring

The harness is intended to run after a successful CodeBuild. Current CI posts
images to ECR with the commit SHA tag; the smoke test pulls the same tag:

```
# After CodeBuild dynamo-inference-public succeeds for <SHA>:
cd 2.projects/dynamo-inference && ./tests/smoke/smoke.sh <SHA>
```

Future: add a second CodeBuild project `dynamo-inference-smoke` that runs
inside the HyperPod cluster (kubeconfig already provisioned) and calls
`smoke.sh` on the same commit the build just produced. Gate PR merges on a
green smoke run.

## Troubleshooting

- **T1 fails** → CodeBuild for this SHA hasn't run or failed. Check
  `aws codebuild list-builds-for-project --project-name dynamo-inference-public`.
- **T3 fails** (missing sm_*) → NCCL was not rebuilt after the 2026-05-04
  NVCC_GENCODE change. Force a full build: `docker build --no-cache -f
  Dockerfile.efa -t efa:local .` and re-run.
- **T4 fails** (0 EFA devices) → pod landed on a non-P5 node or `/dev/infiniband`
  not mounted. Check `kubectl get pod -o jsonpath='{.spec.nodeName}'`.
- **T7 fails** (all-zero counters) → libfabric might be falling back to sockets.
  Inside the pod: `FI_LOG_LEVEL=info fi_info -p efa 2>&1 | grep -i provider`.
  Common cause: secondary VPC CIDR — see EFA/SRD constraints in the repo README.
- **T8 fails** (NVLS init) → missing `NCCL_NVLS_ENABLE=0`. The pod template
  already sets it; check it wasn't overridden by an image env.
- **Latency high on T6** → tiny `opt-125m` generation should finish in under
  3 s. If it's > 10 s, suspect NCCL falling back to single-GPU or a GPU that's
  already under load from another tenant.
