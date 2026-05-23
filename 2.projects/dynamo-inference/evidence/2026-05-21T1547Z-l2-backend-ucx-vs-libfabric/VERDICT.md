# Verdict — L2 backend comparison: LIBFABRIC PASS, UCX FAIL

## LIBFABRIC leg — PASS

`fi_pingpong` cross-node EFA round-trip succeeded with the LIBFABRIC
provider. Both client and server logs show clean exchange with no
errors. See `artifacts/libfabric-client.log` and
`artifacts/libfabric-server.log`.

## UCX leg — FAIL

`ucx_perftest` cross-node bound to link-local 169.254.0.1 (EC2
metadata IP) instead of the EFA fabric. No actual cross-node packets
reached the peer. UCX is unable to use EFA RDM endpoints when the pod
runs with `hostNetwork:true`.

This is consistent with the application-layer failure in
`../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/`: vLLM's
NixlConnector default UCX backend cannot transfer KV between
PrefillWorker and DecodeWorker, so decode crashes with
`NIXL_ERR_BACKEND` on first request.

## nixlbench build attempts — 5 FAILs

The setup logs document 5 sequential attempts to build nixlbench
in-pod. All failed before the rev8 Dockerfile changes. Common error
patterns from those logs:
- `Dependency lookup for etcd-cpp-api with method 'pkg-config' failed`
- `error while loading shared libraries: libgflags.so.2.2`

These fed directly into the rev8 build #19 fix: source-build
etcd-cpp-apiv3, write a manual `.pc`, install runtime t64 packages.

## Conclusion

For NIXL on EFA RDM with `hostNetwork:true`:
- **LIBFABRIC is mandatory.** UCX cannot be used.
- The `kv_connector_extra_config:{backends:["LIBFABRIC"]}` override is
  the production-required configuration for any vLLM Dynamo deployment
  on AWS EFA.

## Linked

- App-layer counterpart: `../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/`
- Working nixlbench: `../2026-05-22T0550Z-nixlbench-multinode-PASS/`
- Working serving: `../2026-05-22T0900Z-disagg-T11-T12-PASS/`
