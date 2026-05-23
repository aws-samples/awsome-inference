# rev8 build #15 nixlbench — PARTIAL (gaps surfaced)

**TL;DR:** First rev8 image (`dynamo-efa:33b2c52e8660`) had `/opt/nixlbench/bin/nixlbench` correctly placed in the runtime stages (silent-COPY-drop fix worked), but two new gaps prevented end-to-end execution.

## What this proved

✅ The silent-COPY-drop fix from commits `bb83ad3` + `33b2c52` works: nixlbench is in the trtllm/vllm runtime stages, no longer dropped.

⚠️ Two new gaps surfaced at runtime:

1. **`libgflags.so.2.2: cannot open shared object file`** — build stage installed `libgflags-dev` (compile-time only). Runtime stages need the actual `.so` packages.
2. **`Invalid runtime: ETCD`** — `etcd-cpp-api` not detected by meson at compile time (no Ubuntu apt package, CMake doesn't ship `.pc`). Without the detection, meson disabled the ETCD runtime entirely; binary fails at flag-parse.

## Why this matters

The PARTIAL outcome motivated the rev8 build #19 fixes that made the
final image work. Without this experiment, those fixes wouldn't exist.

## Successor

`../2026-05-22T0550Z-nixlbench-multinode-PASS/` — image
`520cfc584abb` (build #19) closes both gaps and runs the bench to
46.9 GB/s peak.

## Files

- `manifest.yaml` — status: PARTIAL
- `artifacts/05-pod-a.log`, `05-pod-b.log` — actual `Invalid runtime: ETCD` failure logs
- `artifacts/00-smoke.log` — 7/10 smoke (the 3 FAILs are real, not redirect artifacts)
- `artifacts/VERDICT.md` — original at-the-time verdict (preserved as-is)
- `artifacts/README.md` — original at-the-time README
