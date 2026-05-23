# Round 5 — CodeBuild #16 expectations

**Build ID:** `dynamo-inference-public:91f00670-b5c0-4fec-bb94-59a73a988f5f`
**Source commit:** `e2a09b8` "rev8: fix nixlbench ETCD runtime + runtime libs"
**Compute:** BUILD_GENERAL1_XLARGE (36 vCPU)
**Started:** 2026-05-22T02:27:58Z

## What this build adds vs. build #15 (33b2c52e8660)

1. **etcd-cpp-apiv3 v0.15.4 source build** in `networking-builder` stage,
   installed to `/usr/local`, before nixlbench. Provides:
   - `pkg-config --exists etcd-cpp-api` → succeeds at meson setup
   - `meson configure` shows ETCD runtime enabled
   - Apt deps added: `libcpprest-dev libprotobuf-dev libgrpc-dev
     libgrpc++-dev protobuf-compiler-grpc`
2. **Meson config flags** for explicit etcd path discovery:
   - `-Detcd_inc_path=/usr/local/include`
   - `-Detcd_lib_path=/usr/local/lib`
3. **Runtime libs** in trtllm-stage AND vllm-stage:
   - `apt-get install libgflags2.2 libtomlplusplus3` (after the
     `nixl>=1.0.0` pip install)
   - Inline assertion: `nixlbench --help > /dev/null 2>&1` to fail-loud
     if libs missing

## Expected build time

- Build phase: ~62 min (was 60 min for #15) — adds etcd-cpp-apiv3 cmake
  build (~3-5 min) and runtime apt installs (~30s × 2 stages)
- POST_BUILD: ~30 min (Trivy + SBOM + ECR push, unchanged from #15)
- **Total ETA: ~95 min** → finish ~04:00Z

## Validation steps when SUCCEEDED

1. Get image SHA from build logs (last 12 chars of commit, e.g.
   `${ECR_REGISTRY}/dynamo-efa:e2a09b8XXXXX`)
2. Re-claim H100 lock
3. Run `tests/smoke.sh` — expect all 10 PASS this time (vs. 7/10 last
   round). Critical assertions:
   - `nixlbench --help` runs (was FAIL — `libgflags.so.2.2` missing)
   - `nixl_example LIBFABRIC self-test` (was FAIL — same root cause)
4. Update bench manifest to remove the apt-install workaround:
   ```bash
   sed -i '/apt-get update -qq && apt-get install/,+2d' \
     benchmarks/nixl-bench/deploy/nixlbench-libfabric-vram.yaml
   ```
5. Run `./benchmarks/nixl-bench/scripts/run-multinode.sh` — expect
   non-zero counter deltas this time.

## Pass criteria (round 5)

- nixlbench reaches steady-state cross-node bench (no "Invalid runtime: ETCD")
- pre/post counter delta on both NICs shows non-zero `rdma_read_bytes`
  (NIXL libfabric uses fi_read, not fi_write — confirmed in earlier
  rounds).
- pod-a and pod-b both report a transfer summary table.

## Fail-back path

If round 5 still fails, the next debug step is to inspect the rev8
nixlbench's compile-time runtime registration. The meson build
sub-directory `src/runtime/etcd/` may need `HAVE_ETCD=1` — the current
meson invocation passes `-Detcd_inc_path` / `-Detcd_lib_path` but
doesn't pass `-DHAVE_ETCD=1`. Need to verify nixlbench's meson script
registers the etcd runtime when those paths are set.
