#!/bin/bash
# =============================================================================
# tests/smoke/smoke.sh — on-cluster smoke test for dynamo-efa
# =============================================================================
# Runs the 10-gate testing criteria (see tests/README.md § Criteria).
# Blocking gates: T1–T7. Warning gates: T8–T10.
#
# Usage:
#   ./smoke.sh <SHA>                 # pulls ECR/${ECR_REPO_PREFIX}dynamo-efa:<SHA>
#   ./smoke.sh <SHA> <IMAGE_URI>     # explicit URI override
#
# Env overrides:
#   MODEL=facebook/opt-125m          default smoke model (tiny, no HF token)
#   SMOKE_ALLOW_WARN=1               promote warning gates (T8–T10) to pass
#   K8S_NAMESPACE=default
# =============================================================================
set -euo pipefail

SHA="${1:?usage: $0 <SHA> [IMAGE_URI]}"
IMAGE_URI="${2:-}"
MODEL="${MODEL:-facebook/opt-125m}"
K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
SMOKE_ALLOW_WARN="${SMOKE_ALLOW_WARN:-0}"
AWS_REGION="${AWS_REGION:-us-east-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-058264135704}"
ECR_REPO_PREFIX="${ECR_REPO_PREFIX:-}"
ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
POD_NAME="dynamo-smoke-${SHA}"
LOCK_FILE="${HOME}/.claude/cluster-lock-h100.json"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)/../out/${SHA}"

if [ -z "$IMAGE_URI" ]; then
    IMAGE_URI="${ECR}/${ECR_REPO_PREFIX}dynamo-efa:${SHA}"
fi

mkdir -p "$OUT_DIR"
exec > >(tee -a "$OUT_DIR/smoke.log") 2>&1

log()  { echo "[smoke $(date -Is)] $*"; }
fail() { echo "[smoke FAIL] $*" >&2; exit 1; }
warn() { echo "[smoke WARN] $*" >&2; }

BLOCKING_FAILS=()
WARNING_FAILS=()

check_blocking() { local name="$1"; shift; if "$@"; then log "  T${name}: PASS"; else log "  T${name}: FAIL"; BLOCKING_FAILS+=("T${name}"); fi; }
check_warning()  { local name="$1"; shift; if "$@"; then log "  T${name}: PASS"; else log "  T${name}: FAIL"; WARNING_FAILS+=("T${name}"); fi; }

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------
log "=== smoke.sh SHA=${SHA} image=${IMAGE_URI} model=${MODEL} ==="

# Cluster lock (claim H100 pool)
if [ -f "$LOCK_FILE" ]; then
    HOLDER=$(python3 -c "import json;print(json.load(open('$LOCK_FILE')).get('holder') or '')")
    if [ -n "$HOLDER" ] && [ "$HOLDER" != "smoke-${SHA}" ]; then
        fail "cluster-lock-h100 held by '${HOLDER}' — abort"
    fi
fi
python3 -c "
import json,datetime,pathlib
p = pathlib.Path('$LOCK_FILE')
d = json.loads(p.read_text()) if p.exists() else {}
d.update({'holder':'smoke-${SHA}','claimed_at':datetime.datetime.utcnow().isoformat()+'Z','purpose':'dynamo-efa smoke'})
p.write_text(json.dumps(d, indent=2))
"
log "claimed H100 lock"

release_lock() {
    python3 -c "
import json,pathlib
p = pathlib.Path('$LOCK_FILE')
d = json.loads(p.read_text()) if p.exists() else {}
d.update({'holder':None,'claimed_at':None,'purpose':None,'released_at':__import__('datetime').datetime.utcnow().isoformat()+'Z'})
p.write_text(json.dumps(d, indent=2))
" || true
}
teardown() {
    log "teardown: deleting pod ${POD_NAME}"
    kubectl delete pod "$POD_NAME" -n "$K8S_NAMESPACE" --ignore-not-found --grace-period=30 --timeout=60s || true
    release_lock
}
trap teardown EXIT

# -----------------------------------------------------------------------------
# T1 — Image exists in ECR
# -----------------------------------------------------------------------------
log "T1 image pushed to ECR"
aws ecr describe-images \
    --repository-name "${ECR_REPO_PREFIX}dynamo-efa" \
    --image-ids "imageTag=${SHA}" \
    --region "$AWS_REGION" \
    --output json > "$OUT_DIR/ecr-describe.json" 2>&1 \
    || fail "image ${IMAGE_URI} not in ECR — run CodeBuild first"
log "  T1: PASS"

# -----------------------------------------------------------------------------
# T2 — Image sanity (labels + size)
# -----------------------------------------------------------------------------
log "T2 image sanity"
SIZE_GB=$(jq -r '.imageDetails[0].imageSizeInBytes' "$OUT_DIR/ecr-describe.json" | awk '{printf "%.1f",$1/1024/1024/1024}')
log "  image size: ${SIZE_GB} GB"
if awk "BEGIN{exit !(${SIZE_GB} < 52)}"; then log "  T2: PASS"; else BLOCKING_FAILS+=("T2"); log "  T2: FAIL (>52 GB)"; fi

# -----------------------------------------------------------------------------
# T4 — Deploy pod with EFA, wait ready
# -----------------------------------------------------------------------------
log "T4 deploy smoke pod"
kubectl delete pod "$POD_NAME" -n "$K8S_NAMESPACE" --ignore-not-found --grace-period=5 >/dev/null 2>&1 || true
sed -e "s|SMOKE_POD_NAME|${POD_NAME}|g" \
    -e "s|SMOKE_IMAGE_URI|${IMAGE_URI}|g" \
    -e "s|SMOKE_SHA|${SHA}|g" \
    -e "s|SMOKE_MODEL|${MODEL}|g" \
    "$(dirname "$0")/smoke-pod.yaml" > "$OUT_DIR/smoke-pod.rendered.yaml"
kubectl apply -f "$OUT_DIR/smoke-pod.rendered.yaml"

log "waiting for pod Ready (up to 10 min)…"
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$K8S_NAMESPACE" --timeout=600s \
    || { kubectl describe pod "$POD_NAME" -n "$K8S_NAMESPACE" > "$OUT_DIR/pod-describe.txt"; kubectl logs "$POD_NAME" -n "$K8S_NAMESPACE" > "$OUT_DIR/pod-logs.txt" 2>&1; fail "pod never Ready"; }

kubectl describe pod "$POD_NAME" -n "$K8S_NAMESPACE" > "$OUT_DIR/pod-describe.txt"

# EFA visible?
kubectl exec -n "$K8S_NAMESPACE" "$POD_NAME" -- fi_info -p efa > "$OUT_DIR/fi_info.txt" 2>&1 || true
EFA_DEVS=$(grep -c '^provider: efa' "$OUT_DIR/fi_info.txt" || true)
log "  EFA devices: ${EFA_DEVS}"
if [ "$EFA_DEVS" -ge 1 ]; then log "  T4: PASS"; else BLOCKING_FAILS+=("T4"); log "  T4: FAIL"; fi

# -----------------------------------------------------------------------------
# T3 — Fat-binary NCCL
# -----------------------------------------------------------------------------
log "T3 NCCL fat-binary arches"
kubectl exec -n "$K8S_NAMESPACE" "$POD_NAME" -- \
    bash -c 'strings /usr/local/nccl/lib/libnccl.so.2.30.3 2>/dev/null | grep -oE "sm_[0-9]+" | sort -u' \
    > "$OUT_DIR/nccl-arches.txt" 2>&1 || true
EXPECTED="sm_80 sm_86 sm_89 sm_90 sm_100 sm_120"
MISSING=""
for arch in $EXPECTED; do grep -qx "$arch" "$OUT_DIR/nccl-arches.txt" || MISSING="$MISSING $arch"; done
if [ -z "$MISSING" ]; then log "  T3: PASS"; else BLOCKING_FAILS+=("T3"); log "  T3: FAIL missing:${MISSING}"; fi

# -----------------------------------------------------------------------------
# T5 — Server boots (/v1/models) — poll up to 8 min (model load)
# -----------------------------------------------------------------------------
log "T5 vLLM /v1/models (polling up to 8 min for model load)"
T5_PASS=0
for i in $(seq 1 48); do
    if kubectl exec -n "$K8S_NAMESPACE" "$POD_NAME" -- \
        curl -sf http://127.0.0.1:8000/v1/models > "$OUT_DIR/v1-models.json" 2>&1; then
        T5_PASS=1
        log "  T5: PASS (after $((i*10))s)"
        break
    fi
    sleep 10
done
[ "$T5_PASS" = "1" ] || { BLOCKING_FAILS+=("T5"); log "  T5: FAIL (8 min timeout)"; kubectl logs "$POD_NAME" -n "$K8S_NAMESPACE" | tail -40 >> "$OUT_DIR/v1-models.json"; }

# -----------------------------------------------------------------------------
# T6 — Chat completion
# -----------------------------------------------------------------------------
log "T6 chat completion"
T0=$(date +%s%N)
kubectl exec -n "$K8S_NAMESPACE" "$POD_NAME" -- curl -sf -X POST http://127.0.0.1:8000/v1/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"Hello,\",\"max_tokens\":64,\"temperature\":0}" \
    > "$OUT_DIR/completion.json" 2>&1 || true
T1=$(date +%s%N)
LAT_MS=$(( (T1-T0)/1000000 ))
log "  latency: ${LAT_MS} ms"
TEXT=$(jq -r '.choices[0].text // empty' "$OUT_DIR/completion.json" 2>/dev/null || true)
if [ -n "$TEXT" ]; then log "  T6: PASS (\"$(echo "$TEXT" | head -c 60)…\")"; else BLOCKING_FAILS+=("T6"); log "  T6: FAIL"; fi

# -----------------------------------------------------------------------------
# T7 — RDMA actually used (the critical one)
# -----------------------------------------------------------------------------
log "T7 RDMA hw_counters"
kubectl exec -n "$K8S_NAMESPACE" "$POD_NAME" -- \
    bash -c 'for f in /sys/class/infiniband/rdmap*/ports/1/hw_counters/*; do echo "$(basename $(dirname $(dirname $(dirname $f))))/$(basename $f): $(cat $f 2>/dev/null)"; done' \
    > "$OUT_DIR/hw_counters.txt" 2>&1 || true
# Expect ANY of rdma_read_bytes/rdma_write_bytes/tx_bytes to be nonzero across devices.
BYTES=$(awk -F': ' '/_bytes: [0-9]+$/ {s+=$2} END{print s+0}' "$OUT_DIR/hw_counters.txt")
log "  total _bytes counters: ${BYTES}"
if [ "${BYTES:-0}" -gt 0 ]; then log "  T7: PASS"; else BLOCKING_FAILS+=("T7"); log "  T7: FAIL (TCP fallback suspected)"; fi

# -----------------------------------------------------------------------------
# T8 — No NVLS / NCCL WARN
# -----------------------------------------------------------------------------
log "T8 NCCL WARN scan"
kubectl logs "$POD_NAME" -n "$K8S_NAMESPACE" > "$OUT_DIR/pod-logs.txt" 2>&1 || true
if grep -qE "Couldn't initialize NVLS|NCCL WARN|NCCL ERROR" "$OUT_DIR/pod-logs.txt"; then
    WARNING_FAILS+=("T8"); log "  T8: FAIL"
else
    log "  T8: PASS"
fi

# -----------------------------------------------------------------------------
# T9 — SBOM present in image
# -----------------------------------------------------------------------------
log "T9 SBOM files"
kubectl exec -n "$K8S_NAMESPACE" "$POD_NAME" -- \
    bash -c 'ls -la /opt/security/sbom.spdx.json /opt/security/sbom.cyclonedx.json 2>&1 && jq -e . /opt/security/sbom.spdx.json >/dev/null && jq -e . /opt/security/sbom.cyclonedx.json >/dev/null' \
    > "$OUT_DIR/sbom-check.txt" 2>&1 \
    && log "  T9: PASS" || { WARNING_FAILS+=("T9"); log "  T9: FAIL"; }

# -----------------------------------------------------------------------------
# T10 — Teardown clean (measured during trap)
# -----------------------------------------------------------------------------
TEARDOWN_T0=$(date +%s)
# trap runs teardown, we'll time it by reading ran-at from the pod delete line.

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
{
    echo "# smoke ${SHA} summary"
    echo ""
    echo "- image: ${IMAGE_URI}"
    echo "- model: ${MODEL}"
    echo "- size: ${SIZE_GB} GB"
    echo "- EFA devices: ${EFA_DEVS}"
    echo "- completion latency: ${LAT_MS} ms"
    echo "- hw_counters total bytes: ${BYTES}"
    echo "- blocking fails: ${BLOCKING_FAILS[*]:-none}"
    echo "- warning fails: ${WARNING_FAILS[*]:-none}"
} > "$OUT_DIR/summary.md"

echo
cat "$OUT_DIR/summary.md"
echo

if [ "${#BLOCKING_FAILS[@]}" -gt 0 ]; then
    fail "blocking gates failed: ${BLOCKING_FAILS[*]}"
fi
if [ "${#WARNING_FAILS[@]}" -gt 0 ] && [ "$SMOKE_ALLOW_WARN" != "1" ]; then
    fail "warning gates failed: ${WARNING_FAILS[*]} (set SMOKE_ALLOW_WARN=1 to override)"
fi

log "=== smoke.sh PASS for ${SHA} ==="
