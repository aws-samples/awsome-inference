#!/usr/bin/env bash
# Build both images (Module 1 + Module 2) in dependency order.
#
# Usage:
#   ./scripts/build.sh                  # local tags
#   ./scripts/build.sh $ECR_REPO        # also tag for ECR push
#
# Environment overrides:
#   NETWORKING_BASE   default: networking-base:v5
#   TRTLLM_IMAGE      default: nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.0.1
#   VLLM_IMAGE        default: nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.0.1

set -euo pipefail

REPO_PREFIX="${1:-}"
NETWORKING_BASE="${NETWORKING_BASE:-networking-base:v5}"
TRTLLM_IMAGE="${TRTLLM_IMAGE:-nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.0.1}"
VLLM_IMAGE="${VLLM_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.0.1}"

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

cd "$REPO_ROOT"

echo "=============================================="
echo "Step 1/3: networking-base:v5 (EFA + libfabric)"
echo "=============================================="
docker build -t networking-base:v5 01-networking-base/

echo "=============================================="
echo "Step 2/3: efa-networking:v1 (SBOM + CVE)"
echo "=============================================="
docker build \
  --build-arg "NETWORKING_BASE=${NETWORKING_BASE}" \
  -f docker/Dockerfile.efa \
  -t efa-networking:v1 \
  .

echo "=============================================="
echo "Step 3/3: dynamo-combined-efa:v1 (vLLM+TRT-LLM)"
echo "=============================================="
docker build \
  --build-arg "NETWORKING_BASE=${NETWORKING_BASE}" \
  --build-arg "TRTLLM_IMAGE=${TRTLLM_IMAGE}" \
  --build-arg "VLLM_IMAGE=${VLLM_IMAGE}" \
  -f docker/Dockerfile.dynamo-combined-efa \
  -t dynamo-combined-efa:v1 \
  .

if [[ -n "$REPO_PREFIX" ]]; then
  echo "=============================================="
  echo "Tagging for $REPO_PREFIX"
  echo "=============================================="
  docker tag networking-base:v5      "$REPO_PREFIX/networking-base:v5"
  docker tag efa-networking:v1       "$REPO_PREFIX/efa-networking:v1"
  docker tag dynamo-combined-efa:v1  "$REPO_PREFIX/dynamo-combined-efa:v1"
  echo "Run 'docker push $REPO_PREFIX/<image>:<tag>' when ready."
fi

echo ""
echo "=== Built images ==="
docker images | grep -E "networking-base|efa-networking|dynamo-combined-efa" | head

# ------------------------------------------------------------
# Extract SBOM + CVE reports from each image that has them
# ------------------------------------------------------------
SBOM_OUT="${SBOM_OUT:-${REPO_ROOT}/out/sbom}"
mkdir -p "${SBOM_OUT}"
extract_sbom() {
  local img="$1"
  local sub="$2"
  local cid
  cid=$(docker create "${img}" 2>/dev/null) || { echo "[build.sh] skip ${img} (no image)"; return; }
  mkdir -p "${SBOM_OUT}/${sub}"
  docker cp "${cid}:/opt/security/." "${SBOM_OUT}/${sub}/" 2>/dev/null &&     echo "[build.sh] SBOM of ${img} -> ${SBOM_OUT}/${sub}/" ||     echo "[build.sh] (${img} has no /opt/security — skipping)"
  docker rm "${cid}" >/dev/null
}
extract_sbom efa-networking:v5        efa-networking-v5     || true
extract_sbom dynamo-combined-efa:v1   dynamo-combined-efa-v1 || true

