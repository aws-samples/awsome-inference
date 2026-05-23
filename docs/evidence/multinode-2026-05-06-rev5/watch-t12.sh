#!/bin/bash
# watch-t12.sh — poll the rev5 evidence dir for T12d outcome
#
# Watches docs/evidence/multinode-2026-05-06-rev5/t12-completions.log for
# signs of PASS or NO-GO and prints the next action when detected.
#
# PASS signal:  log contains "choices" (OpenAI completions schema) AND
#               "text" field with non-empty content
# NO-GO signal: log contains "data": [] OR "404" OR "error" OR is absent
#               after 15 min of pod-ready state
#
# Usage (from the rev5 dir):
#   ./watch-t12.sh
#
# Exit codes:
#   0  — PASS detected, rev5-PASS gist is the next action
#   2  — NO-GO detected, ai-dynamo upstream issue is the next action
#   130 — user Ctrl+C
set -euo pipefail

LOG="t12-completions.log"
GIST="https://gist.github.com/dmvevents/b1c8d9a376a12f3b0842c3c3fc335ffc"
POLL=15

cd "$(dirname "$0")"

echo "=== rev5 T12 watcher ==="
echo "  watching: $(pwd)/${LOG}"
echo "  polling every ${POLL} s"
echo "  gist with drafts: ${GIST}"
echo ""

check_pass() {
    # OpenAI completions response has "choices" array with "text" field
    python3 -c '
import json, sys
try:
    d = json.load(open("'"${LOG}"'"))
    choices = d.get("choices") or []
    if choices and choices[0].get("text"):
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
' 2>/dev/null
}

check_nogo() {
    # /v1/models returned {"data":[]} OR HTTP 404/500 text OR error field
    if grep -qE '"data":\s*\[\s*\]|404|"error"' "${LOG}" 2>/dev/null; then
        return 0
    fi
    return 1
}

start_time=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - start_time ))
    mins=$(( elapsed / 60 ))

    if [ ! -f "${LOG}" ]; then
        printf "\r  [%3dm] %s" "${mins}" "waiting for ${LOG}..."
        sleep "${POLL}"
        continue
    fi

    if check_pass; then
        echo ""
        echo ""
        echo "=========================================="
        echo "  T12d PASS DETECTED"
        echo "=========================================="
        echo ""
        echo "  ${LOG} contains a valid OpenAI completion response."
        echo "  Preview:"
        python3 -c "
import json
d = json.load(open('${LOG}'))
print('    finish_reason:', d['choices'][0].get('finish_reason','?'))
print('    text:', d['choices'][0].get('text','')[:200])
print('    usage:', d.get('usage',{}))
"
        echo ""
        echo "  NEXT ACTION:"
        echo "    1. Open ${GIST}"
        echo "    2. Fill pr72-rev5-PASS-draft.md with the SHA + timing"
        echo "       numbers + this curl response"
        echo "    3. Fire: gh pr comment 72 --repo aws-samples/awsome-inference --body @filled.md"
        echo "    4. Update README.md T12d row: BLOCKED → PASS"
        echo ""
        exit 0
    fi

    if check_nogo; then
        echo ""
        echo ""
        echo "=========================================="
        echo "  T12d NO-GO DETECTED"
        echo "=========================================="
        echo ""
        echo "  ${LOG} shows the same symptom as rev4 (0 instances / 404 / error)"
        echo "  1.1.0 did NOT fix the upstream KubeDiscoveryClient issue."
        echo ""
        echo "  NEXT ACTION:"
        echo "    1. Open ${GIST}"
        echo "    2. Fill ai-dynamo-upstream-issue-NOGO-draft.md with:"
        echo "       - the 1.1.0 rev5 evidence paths"
        echo "       - docker labels confirming 1.1.0 in-image"
        echo "    3. File at https://github.com/ai-dynamo/dynamo/issues/new"
        echo "    4. Post rev5-NOGO comment on PR #72 linking the upstream issue"
        echo "    5. Update README.md T12d row: BLOCKED → UPSTREAM-TRACKED"
        echo ""
        exit 2
    fi

    printf "\r  [%3dm] %s" "${mins}" "${LOG} present but inconclusive — still polling..."
    sleep "${POLL}"
done
