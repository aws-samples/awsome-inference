#!/bin/bash
# fill-rev5-nogo.sh — auto-populate the NO-GO upstream issue + PR comment
#
# Reads frontend logs + the image SHA and produces:
#   /tmp/rev5-nogo-upstream-issue.md  — ai-dynamo/dynamo issue body
#   /tmp/rev5-nogo-pr-comment.md      — PR #72 comment linking upstream issue
#
# Usage (from the rev5 evidence dir):
#   ./fill-rev5-nogo.sh [IMAGE_SHA]
set -euo pipefail

SHA="${1:-9467d1460c71}"
cd "$(dirname "$0")"
EVIDENCE_DIR="$(pwd)"
UPSTREAM=/tmp/rev5-nogo-upstream-issue.md
PR_COMMENT=/tmp/rev5-nogo-pr-comment.md

# -----------------------------------------------------------------------
# Collect evidence
# -----------------------------------------------------------------------
KUBE_LOG="${EVIDENCE_DIR}/t12-kubediscovery.log"
PREFILL_LOG="${EVIDENCE_DIR}/t12-prefill-full.log"
DECODE_LOG="${EVIDENCE_DIR}/t12-decode-full.log"
DGDS="${EVIDENCE_DIR}/t12-dgds.txt"

DATE_UTC=$(date -u +%FT%TZ)

# Extract the "0 instances" line count from Frontend log
ZERO_INST_COUNT=0
if [ -f "${KUBE_LOG}" ]; then
    ZERO_INST_COUNT=$(grep -c "returning 0 instances" "${KUBE_LOG}" 2>/dev/null || echo 0)
fi

# Extract the actual namespace Workers registered to
WORKER_NS="<fill from prefill log>"
if [ -f "${PREFILL_LOG}" ]; then
    WORKER_NS=$(grep -oE "namespace=[a-z0-9-]+" "${PREFILL_LOG}" 2>/dev/null | head -1 | cut -d= -f2)
    [ -z "${WORKER_NS}" ] && WORKER_NS="<not found>"
fi

# -----------------------------------------------------------------------
# Generate upstream issue body
# -----------------------------------------------------------------------
cat > "${UPSTREAM}" <<EOF
# \`KubeDiscoveryClient\` returns \`0 instances\` in disaggregated vLLM on Dynamo 1.1.0 (persists from 1.0.1)

## Summary

Frontend \`/v1/completions\` returns \`{"data":[]}\` and HTTP 404 on \`/v1/models\` in a canonical single-DGD disaggregated-vLLM deployment because the Frontend \`KubeDiscoveryClient\` polls \`0 instances for query=AllEndpoints\` every 10 s (observed **${ZERO_INST_COUNT} times** in our evidence log), even though both \`PrefillWorker\` and \`DecodeWorker\` register endpoints in etcd under the same namespace (\`${WORKER_NS}\`) that Frontend queries.

Reproduces on **Dynamo 1.0.1 and 1.1.0** operator + runtime. Blocked on disaggregated-vLLM end-to-end serving on AWS EFA P5.48xlarge H100.

## Environment

| Component | Version |
|---|---|
| Dynamo operator | 1.0.1 (also reproduced on 1.1.0 runtime) |
| Dynamo runtime | \`nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.1.0\` |
| Image SHA | \`dynamo-efa:${SHA}\` |
| vLLM | 0.17.1 |
| Kubernetes | 1.32 (Amazon EKS) |
| NIXL | 1.0.1 |
| libfabric | 2.4.0amzn3.0 |
| AWS EFA installer | 1.48.0 |
| Hardware | 2× Amazon EC2 P5.48xlarge (8× H100 each, 32 EFA rails/node) |

## Minimal repro

1. Apply canonical single-DGD manifest matching \`examples/backends/vllm/deploy/disagg.yaml\`:
   https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml
2. Wait for all 3 pods to reach Running + model weights loaded (~5 min).
3. Observe Frontend logs (every 10 s):
   \`\`\`
   [INFO] dynamo_runtime::discovery::kube: KubeDiscoveryClient::list returning 0 instances for query=AllEndpoints
   \`\`\`
4. \`curl /v1/models\` returns \`{"object":"list","data":[]}\`.

## What we verified

- **Workers register successfully in etcd.** Both prefill and decode log \`Registering endpoint: namespace=${WORKER_NS}, component=..., endpoint=generate, instance_id=...\`.
- **Namespace strings match.** Frontend env \`DYN_NAMESPACE=${WORKER_NS}\` (via explicit override on all 3 services per rev4 workaround). Workers register at the same string.
- **\`EndpointSlice\` label \`nvidia.com/dynamo-namespace\` matches exactly.** Verified via \`kubectl get endpointslice\`.
- **\`DynamoWorkerMetadata\` CRs exist but have no \`.metadata.labels\`.** We suspect Frontend filters by a predicate (worker-hash annotation on the owning Pod?) but cannot confirm from logs alone.

## What we tried

| Approach | Outcome |
|---|---|
| Separate Frontend / Prefill / Decode DGDs | Each stamped with different suffix → namespace mismatch by design |
| Merged canonical single-DGD (upstream \`disagg.yaml\`) | Same suffix on all services → still 0 instances |
| Override \`DYN_NAMESPACE\` on all 3 services to literal | Workers + Frontend at same namespace string → still 0 instances |
| Set \`DYN_NAMESPACE_WORKER_SUFFIX=""\` to strip suffix | Workers register at unsuffixed namespace → still 0 instances |
| \`DYN_DISCOVERY_BACKEND=etcd\` (override default \`kubernetes\`) | Same symptom regardless of backend |
| Bump Dynamo 1.0.1 → 1.1.0 | Same symptom reproduces |

## Evidence bundles

- [rev2 — NIXL plugin + nccl-tests fixes](https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-05-rev2/README.md)
- [rev3 — single-DGD canonical layout](https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-05-rev3/README.md)
- [rev4 — worker suffix override](https://github.com/dmvevents/awsome-inference-1/tree/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-06-rev4)
- [rev5 — 1.1.0 reproduction](https://github.com/dmvevents/awsome-inference-1/tree/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-06-rev5)

## Questions for the Dynamo runtime team

1. What label / annotation does \`KubeDiscoveryClient::list_and_watch\` filter on when building the instance list for \`query=AllEndpoints\`? The \`DynamoWorkerMetadata\` CRs the operator creates have empty \`.metadata.labels\` — is Frontend expected to match on \`.spec\` fields instead?
2. Is there a pod-level annotation the operator stamps on workers that the Frontend's Kubernetes RBAC needs permission to read but may not have in a default operator install?
3. Is this a known issue in operator 1.0.1 / runtime 1.1.0 with a planned fix in a later version?

## Requested fix

Either:
- Frontend \`DYN_NAMESPACE\` auto-derives the same suffix the operator stamps on workers, and the \`KubeDiscoveryClient\` label/predicate is documented and included in the default operator RBAC, OR
- The operator exposes \`dynamoNamespace\` as a user-settable CRD field preserved across reconciles and stamps it identically on every service including Frontend.

## Repo cross-reference

Blocks [aws-samples/awsome-inference#72](https://github.com/aws-samples/awsome-inference/pull/72) from closing its T12 gate. Image side of that PR passes every other gate on the exact Dynamo operator + runtime versions above.
EOF

# -----------------------------------------------------------------------
# Generate PR #72 NO-GO comment (links the filed upstream issue)
# -----------------------------------------------------------------------
cat > "${PR_COMMENT}" <<EOF
## rev5 — 1.1.0 reproduces the KubeDiscoveryClient issue; filed upstream (${DATE_UTC})

Objective 1 / KR 1.2 **NO-GO on T12 end-to-end**. Dynamo 1.1.0 (\`dynamo-efa:${SHA}\`) did not resolve the Frontend discovery wiring issue isolated in rev4.

Filed upstream as **[ai-dynamo/dynamo#<ISSUE-NUM>](https://github.com/ai-dynamo/dynamo/issues/<ISSUE-NUM>)** with the full evidence bundle from rev5.

### Gate status (superseding rev2/rev3/rev4)

| Gate | Status |
|---|---|
| T1–T10 image smoke | PASS on 1.1.0 |
| T11 cross-node NCCL AllReduce | PASS |
| T11b intra-node \`nccl-tests\` | PASS |
| NIXL plugin load | PASS |
| \`--kv-transfer-config\` accepted | PASS |
| Worker + Frontend namespace alignment | PASS (via rev4 overrides) |
| **T12 \`/v1/completions\` end-to-end** | **BLOCKED — upstream issue tracked** |

### Recommendation

**Merge PR #72 as "image side green, T12 blocked on upstream operator fix."**

Every gate the image can influence passes. The \`KubeDiscoveryClient\` filter predicate is internal to \`dynamo_runtime::discovery::kube::daemon\` and is orthogonal to the Dockerfile + DGD layout this PR contributes. When the upstream fix lands in a future operator release, PR #72's image will transparently work end-to-end with no rebuild required.

### Evidence

- [rev5 README](https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-06-rev5/README.md)
- [t12-kubediscovery.log](https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-06-rev5/t12-kubediscovery.log) (${ZERO_INST_COUNT} "0 instances" log lines)
- [Upstream issue](https://github.com/ai-dynamo/dynamo/issues/<ISSUE-NUM>)

cc @AlexIankoulski
EOF

echo "=== NO-GO drafts written ==="
echo ""
echo "Upstream issue body: ${UPSTREAM}"
echo "PR #72 NO-GO comment: ${PR_COMMENT}"
echo ""
echo "Fire sequence:"
echo "  1. Review both drafts (fill any <tags> that didn't auto-populate)"
echo "  2. File the upstream issue:"
echo "     gh issue create --repo ai-dynamo/dynamo \\"
echo "       --title 'KubeDiscoveryClient returns 0 instances in disagg vLLM on 1.0.1+1.1.0' \\"
echo "       --body-file ${UPSTREAM}"
echo "  3. Note the issue number, replace <ISSUE-NUM> in ${PR_COMMENT} via sed"
echo "  4. Fire the PR #72 comment:"
echo "     gh pr comment 72 --repo aws-samples/awsome-inference --body-file ${PR_COMMENT}"
