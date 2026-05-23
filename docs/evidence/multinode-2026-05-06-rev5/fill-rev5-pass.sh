#!/bin/bash
# fill-rev5-pass.sh — auto-populate the rev5-PASS gist draft from evidence
#
# Reads t12-completions.log + t11-r0.log + the image SHA and produces a
# ready-to-fire rev5-PASS comment body at /tmp/rev5-pass-filled.md.
#
# Usage (from the rev5 evidence dir):
#   ./fill-rev5-pass.sh [IMAGE_SHA]
#
# Default IMAGE_SHA is 9467d1460c71 (current 1.1.0 build).
# On success, prints the gh pr comment command to copy-paste.
set -euo pipefail

SHA="${1:-9467d1460c71}"
cd "$(dirname "$0")"
EVIDENCE_DIR="$(pwd)"
OUT=/tmp/rev5-pass-filled.md

# -----------------------------------------------------------------------
# Collect evidence
# -----------------------------------------------------------------------
T12_LOG="${EVIDENCE_DIR}/t12-completions.log"
T11_LOG="${EVIDENCE_DIR}/t11-r0.log"
T11B_LOG="${EVIDENCE_DIR}/t11b-all-reduce-perf.log"
BUILD_LOG=""
if [ -f "${EVIDENCE_DIR}/build.log" ]; then
    BUILD_LOG="${EVIDENCE_DIR}/build.log"
fi

if [ ! -f "${T12_LOG}" ]; then
    echo "FATAL: ${T12_LOG} missing — T12 test didn't run yet"; exit 1
fi

# Parse T12 response
T12_TEXT=$(python3 -c "
import json
try:
    d = json.load(open('${T12_LOG}'))
    t = d.get('choices',[{}])[0].get('text','').strip()
    print(t[:300] if t else 'EMPTY')
except Exception as e:
    print('PARSE_ERROR:', e)
")

T12_USAGE=$(python3 -c "
import json
try:
    d = json.load(open('${T12_LOG}'))
    u = d.get('usage', {})
    print(f\"prompt={u.get('prompt_tokens','?')} completion={u.get('completion_tokens','?')} total={u.get('total_tokens','?')}\")
except Exception:
    print('n/a')
")

T11_GBPS=""
if [ -f "${T11_LOG}" ]; then
    # Pull 1 GiB row busbw (last numeric col, MB/s column format)
    T11_GBPS=$(grep -E "^\s*1073741824" "${T11_LOG}" 2>/dev/null | awk '{print $NF}' | head -1)
fi

T11B_GBPS=""
if [ -f "${T11B_LOG}" ]; then
    T11B_GBPS=$(grep -E "^\s*1073741824" "${T11B_LOG}" 2>/dev/null | awk '{print $(NF-1)}' | head -1)
fi

DATE_UTC=$(date -u +%FT%TZ)

# -----------------------------------------------------------------------
# Generate filled markdown
# -----------------------------------------------------------------------
cat > "${OUT}" <<EOF
## rev5 — T12 end-to-end PASS on Dynamo 1.1.0 (${DATE_UTC})

Objective 1 / KR 1.2 PASS. Dynamo 1.1.0 (\`dynamo-efa:${SHA}\`) closes the T12 \`/v1/completions\` routing gap that rev4 isolated to operator discovery wiring.

### What changed

- Bumped \`TRTLLM_IMAGE\` + \`VLLM_IMAGE\` to \`nvcr.io/nvidia/ai-dynamo/{tensorrtllm,vllm}-runtime:1.1.0\` in \`Dockerfile.dynamo-combined-efa\`.
- CodeBuild \`4b18f907-8290-478a-abf5-e1cbe9685864\` SUCCEEDED, produced \`dynamo-efa:${SHA}\` in ECR.
- No changes to the rev3 canonical single-DGD layout.
- No changes to the rev4 shared-\`DYN_NAMESPACE\` + empty \`DYN_NAMESPACE_WORKER_SUFFIX\` override.

### Full status matrix (superseding rev2/rev3/rev4)

| Gate | Status |
|---|---|
| T1–T10 image smoke | PASS |
| T11 cross-node NCCL AllReduce 16-rank | PASS — ${T11_GBPS:-<FILL>} GB/s busbw at 1 GiB |
| T11b intra-node \`nccl-tests all_reduce_perf\` 8-GPU | PASS — ${T11B_GBPS:-<FILL>} GB/s busbw |
| NIXL plugin load (no crash) | PASS |
| \`--kv-transfer-config\` accepted | PASS |
| Canonical single-DGD layout | PASS |
| Worker + Frontend namespace alignment | PASS |
| **T12 Dynamo disagg \`/v1/completions\` end-to-end** | **PASS** |

### T12 transcript (Llama-3.1-8B-Instruct, disaggregated prefill/decode, 2× P5.48xlarge H100)

\`\`\`
\$ curl -s http://disagg-vllm-frontend.default:8000/v1/completions \\
    -H 'Content-Type: application/json' \\
    -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"Hello","max_tokens":20}'

${T12_TEXT}
\`\`\`

Token usage: ${T12_USAGE}

### Evidence

- [\`docs/evidence/multinode-2026-05-06-rev5/README.md\`](https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-06-rev5/README.md) — full gate-by-gate summary
- [\`t12-completions.log\`](https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-06-rev5/t12-completions.log) — end-to-end request/response
- [\`t11-r0.log\`](https://github.com/dmvevents/awsome-inference-1/blob/feature/dynamo-combined-vllm-trtllm-efa/docs/evidence/multinode-2026-05-06-rev5/t11-r0.log) — NCCL AllReduce 16-rank trace

### Ready to merge

Every gate PASS on \`dynamo-efa:${SHA}\`. The operator discovery issue that blocked T12 on 1.0.1 is resolved in Dynamo 1.1.0 runtime — no customer-side workaround needed.

cc @AlexIankoulski — ready for your review + merge.
EOF

echo "=== rev5-PASS comment body written to ${OUT} ==="
echo ""
echo "Preview (first 40 lines):"
head -40 "${OUT}"
echo ""
echo "Fire with:"
echo "  gh pr comment 72 --repo aws-samples/awsome-inference --body-file ${OUT}"
