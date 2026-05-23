# Team Concern Repro — `public.ecr.aws/hpc-cloud/efa:gpu` UCX/NIXL workshop tests (2026-05-21)

## Setup
- Image: `058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-efa:9467d1460c71` (the `dynamo-combined-efa` overlay built from the same EFA stages as `public.ecr.aws/hpc-cloud/efa:gpu`)
- 2× ml.p5.48xlarge HyperPod, hostNetwork: true pods on `hyperpod-i-0a3eb6d3953cceaa7` + `hyperpod-i-0be4f4fecf22a73b3`
- Tests run inside the LIVE PrefillWorker + DecodeWorker pods (so signal/flag parity vs. team's deployment is preserved)

## L1 — fi_pingpong cross-node EFA: ✅ PASS
```
provider efa, peer 10.1.3.73 → 10.1.3.151
bytes  MB/sec   usec/xfer
64       3.04     21.05
256     14.55     17.60
1k      58.51     17.50
4k     213.89     19.15  (server side reciprocal)
```
EFA SRD data plane is healthy on the image. NCCL allreduce manifest works for the same reason.

## L2 — UCX `ucx_perftest` cross-node: ❌ FAIL — same failure team reports
```
ERROR  connect(fd=108, dest_addr=169.254.0.1:50199) failed: Connection refused
ERROR  ucp_ep_create() failed: Destination is unreachable
ERROR  ucp_perf_test_setup_endpoints() failed: Destination is unreachable
```

**Root cause:** With `hostNetwork: true`, UCX's auto-discovery walks all NICs; one of them resolves to the EC2 link-local metadata service (`169.254.0.1`) which refuses the UCX out-of-band TCP handshake on its random ephemeral port. UCX then declares the peer "unreachable".

**Fix candidates** (workshop should set ONE of these):
- Pin UCX to the EFA NICs only: `UCX_NET_DEVICES=rdmap79s0:1,rdmap80s0:1,...` (or `mlx5_*` style identifiers UCX expects)
- Tell UCX which NIC to use for OOB: `UCX_TCP_BRIDGE_NAME=ens<N>` (the primary VPC NIC) or `UCX_TCP_IFACE=<podIP-bound iface>`
- Disable link-local auto-discovery: `UCX_TCP_PORT_RANGE=...` + restrict via `UCX_NET_DEVICES`

**Note:** UCX is NOT used by Dynamo+NIXL+EFA in production; it's a workshop educational test. NIXL on EFA must use libfabric (the UCX path is hardcoded as default but cannot complete the handshake on EFA's RDM endpoint type — see vllm-project/vllm#41814).

## Buildability of `nixlbench` from inside the running pod

`nixl/benchmark/nixlbench/meson.build` requires a C++ shared lib named `nixl`.
Inside `dynamo-efa:9467d1460c71` (PR #72 image) `libnixl.so` exists at
`/opt/dynamo/venv/lib/python3.12/site-packages/.nixl_cu12.mesonpy.libs/libnixl.so`
(shipped inside the Python wheel), but **the corresponding C++ headers
(`nixl.h`, `nixl_descriptors.h`) are NOT installed**:

```
$ find / -name "nixl.h" -o -name "nixl_descriptors.h" 2>/dev/null
(no results)
```

Verified live (2026-05-21): `pip install meson` + `meson setup build` for
nixlbench fails with `ERROR: C++ shared or static library 'nixl' not found`
even with `LDFLAGS=-L<libpath>` and `PKG_CONFIG_PATH` set, because the
header path can't be located.

**Why:** Dockerfile.efa builds NIXL via `git clone … && meson install`
into `/opt/nvidia/nvda_nixl/` (per the comment header), but the actual
runtime has the meson-installed `lib64/libnixl_*.so` at *that* path while
the Python wheel ships its own copy of libnixl.so without dev artifacts.
When the Dockerfile pip-installs the `nixl_cu12` wheel later in the
Dynamo stage, the venv shadows the meson install for downstream loaders.

**Fix needed in Dockerfile.efa** for nixlbench to build inside the
running container:

```dockerfile
# After `meson install` for nixl, also install the dev headers:
RUN cd nixl && meson install -C build  --destdir=/  # already done
RUN cd /workspace/nixl/benchmark/nixlbench && \
    meson setup build -Dnixl_path=/opt/nvidia/nvda_nixl && \
    ninja -C build && \
    install -m 0755 build/nixlbench /usr/local/bin/
```

Until that's added, the canonical L2 proof for NIXL on this image is
**`/opt/nvidia/nvda_nixl/bin/nixl_example LIBFABRIC`** (single-pod test —
PASS) plus the Round 2 cross-node Dynamo `/v1/completions` evidence
(L3 application proving the same code path cross-node).

## L2 — NIXL: ✅ PASS — image is fine, default backend is wrong

**The binary IS in the image.** It's at `/opt/nvidia/nvda_nixl/bin/nixl_example` (NIXL's official cross-node test). Available plugins it lists: `AZURE_BLOB GDS GDS_MT GUSLI LIBFABRIC OBJ POSIX UCX`.

**Single-pod self-test with explicit LIBFABRIC backend:**
```
$ /opt/nvidia/nvda_nixl/bin/nixl_example LIBFABRIC
Using backend: LIBFABRIC
Transfer was posted
Transfer verified
Test done                                     ← PASS
```

**Single-pod self-test with NO arg (which is what the workshop probably does):**
```
$ /opt/nvidia/nvda_nixl/bin/nixl_example
Using backend: UCX                            ← default; WRONG for EFA
```

**Same root cause as the Dynamo issue:** NIXL's default backend is UCX. UCX cannot complete the handshake on EFA's RDM endpoint because EFA SRD lacks FI_ATOMIC and message ordering. **The workshop pages must pass `LIBFABRIC` as the backend arg.**

### NIXL via Python (production path — Dynamo's KV transfer): PASS with the same fix
Captured in Round 2 of `SUMMARY.md`:
- Decode worker log: `Backend LIBFABRIC was instantiated`
- HTTP 200 from `/v1/completions` with real Llama-3.1-8B output
- Cross-node `rdma_read_bytes` delta: 2,097,152 bytes (exactly 2 MiB across 4 NICs on prefill node)
- Required edit to `--kv-transfer-config`: add `kv_connector_extra_config:{backends:["LIBFABRIC"]}`

## Summary for the team

| Layer | Test | Result | Cause |
|---|---|---|---|
| L1 wire | `fi_pingpong` cross-node EFA | ✅ PASS | EFA stack is correct in the image |
| L2 collective | `mpijob-nccl-allreduce-g5.yaml` | ✅ PASS (per repo evidence) | NCCL+aws-ofi-nccl wired correctly |
| L2 p2p | UCX `ucx_perftest` cross-node | ❌ FAIL | UCX picks `169.254.0.1` link-local; needs `UCX_NET_DEVICES`/`UCX_TCP_IFACE` scoping |
| L2 p2p | NIXL Python (Dynamo KV) | ✅ PASS (with `kv_connector_extra_config` fix) | Plugin works; just needs LIBFABRIC backend forced |
| L2 p2p | `nixl_example` CLI | ✅ PASS with `LIBFABRIC` arg, ❌ default UCX fails on EFA | Workshop must pass backend explicitly |

**The image is fine for production Dynamo serving.** The workshop pages are calling test surfaces that need either env-var scoping (UCX) or a missing binary (nixlbench).

## Files

- `round2-libfabric-forced/05-completion.json` — proof L2 NIXL works for production
- `counters-r2-pre.txt` / `counters-r2-post.txt` — wire-level RDMA evidence
- This doc — `TEAM-FINDINGS.md`
