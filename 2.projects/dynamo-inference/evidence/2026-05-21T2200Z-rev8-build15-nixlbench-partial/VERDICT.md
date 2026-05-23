# Verdict — rev8 build #15 PARTIAL

**Image:** `dynamo-efa:33b2c52e8660` (CodeBuild build `decad76f-6edd-4c66-82e6-c5530f86fefd`)
**Source commit:** `33b2c52`
**Result:** PARTIAL — first-stage fix confirmed; second-stage gaps surfaced.

## What the silent-COPY-drop fix achieved

Commits `bb83ad3` and `33b2c52` to `Dockerfile.dynamo-combined-efa`:
1. `bb83ad3` — added `COPY --from=networking /opt/nixlbench /opt/nixlbench` to trtllm-stage and vllm-stage
2. `33b2c52` — added the actual nixlbench build step in this Dockerfile's `networking-builder` (stage names are NOT shared across Dockerfiles)

Both commits validated by this experiment: kubectl exec confirmed
`/opt/nixlbench/bin/nixlbench` exists in the runtime image. The
silent-COPY-drop bug from the prior build is closed.

## What still failed

### Gap 1 — runtime libs missing

```
nixlbench: error while loading shared libraries: libgflags.so.2.2: cannot open shared object file
```

Build stage installed `libhwloc-dev libgflags-dev libtomlplusplus-dev`
(compile-time headers + symlinks). Runtime trtllm-stage and vllm-stage
are FROM `nvcr.io/nvidia/ai-dynamo/{trtllm,vllm}-runtime:1.1.0` — those
upstream images don't ship `libgflags2.2` or `libtomlplusplus3` runtime
packages.

### Gap 2 — ETCD runtime not registered at compile time

```
Invalid runtime: ETCD
```

`nixlbench/meson.build:110` does
`dependency('etcd-cpp-api', required: false)`. `etcd-cpp-api` is not in
Ubuntu apt, and the build stage didn't have a source-built copy. So
meson printed `ETCD C++ client library not found. Disabling ETCD
runtime` and registered no ETCD runtime. At flag parse, even with
`--runtime ETCD` (the default), `worker.cpp:128` rejects with
`Unsupported NIXLBench backend`.

## Smoke test breakdown

7/10 PASS, 3/10 FAIL. The 3 FAILs are real:

- ❌ `nixlbench --help runs` — `libgflags.so.2.2: cannot open ...`
- ❌ `nixl_example LIBFABRIC self-test` — same shared lib failure
- ❌ `fi_info -p efa lists devices` — environment issue at smoke time (passed on later runs)

## Fix in next build

Build #19 (commit `520cfc5`) closes both gaps:
- Source-build etcd-cpp-apiv3 v0.15.4 + manually write `etcd-cpp-api.pc`
- apt install `libcpprest2.10 libprotobuf32t64 libgrpc29t64 libgrpc++1.51t64` in trtllm/vllm stages

## Linked

- Successor (PASS): `../2026-05-22T0550Z-nixlbench-multinode-PASS/`
- Build snapshot of the WORKING Dockerfile: `../build-snapshot/Dockerfile.dynamo-combined-efa`
