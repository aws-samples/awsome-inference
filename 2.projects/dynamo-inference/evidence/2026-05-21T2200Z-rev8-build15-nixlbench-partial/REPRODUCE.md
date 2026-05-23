# Reproduce: rev8 build #15 PARTIAL

**This is a historical FAIL.** You should NOT need to reproduce this —
the rev8 build #19 image closes both gaps. This doc is for the rare
case of debugging the build pipeline itself.

## When you'd want to run this

- You're investigating whether nixlbench's runtime-libs or
  etcd-cpp-api detection has changed
- You want to verify the gap-by-gap fix sequence
- You're contributing to the upstream `nixlbench` Dockerfile recipe

## Environment

| Item | Value |
|---|---|
| Image | `${ECR_REGISTRY}/dynamo-efa:33b2c52e8660` (rev8 build #15) |
| CodeBuild ID | `decad76f-6edd-4c66-82e6-c5530f86fefd` |
| Source commit | `33b2c52` (NOT the working `520cfc5`) |

## Reproduce

```bash
export ECR_REGISTRY="<your registry>"
export IMAGE_TAG="33b2c52e8660"

# Use the same nixlbench manifest as the PASS run, just substitute the older tag
sed -e 's|058264135704\.dkr\.ecr\.us-east-2\.amazonaws\.com|${ECR_REGISTRY}|g' \
    -e "s|REV8_REBUILD_TAG|$IMAGE_TAG|g" \
    ../2026-05-22T0550Z-nixlbench-multinode-PASS/derived/nixlbench-template.yaml \
    | envsubst '${ECR_REGISTRY}' \
    | kubectl apply -f -

# Wait for both pods Ready
kubectl wait pod nixlbench-a nixlbench-b --for=condition=Ready -n default --timeout=300s

# Tail pod logs — expect "libgflags.so.2.2: cannot open" or "Invalid runtime: ETCD"
kubectl logs -n default nixlbench-a
kubectl logs -n default nixlbench-b
```

## Expected outcome

Both pods exit with one of:
- `nixlbench: error while loading shared libraries: libgflags.so.2.2: cannot open shared object file`
- `Invalid runtime: ETCD` (if the smoke fix below was applied but etcd-cpp-api wasn't built)

If you see neither error and the bench completes — congrats, the
upstream image has fixed the gaps and our workaround is no longer
needed.

## Cleanup

```bash
kubectl delete pod nixlbench-a nixlbench-b -n default
```

## What to do AFTER reproducing

Compare with `../build-snapshot/Dockerfile.dynamo-combined-efa` (the
WORKING version at commit `520cfc5`) to see exactly which lines closed
each gap.
