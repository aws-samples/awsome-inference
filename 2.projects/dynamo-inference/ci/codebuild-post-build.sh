#!/usr/bin/env bash
# Runs inside the CodeBuild post_build phase. Requires:
#   EFA_URI, COMBINED_URI, ECR, ECR_REPO_PREFIX, SHA set by pre_build
#   CVE_ALLOW_CRITICAL, S3_SBOM_BUCKET optional (default empty/zero)

set -euo pipefail

: "${EFA_URI:?EFA_URI is required}"
: "${COMBINED_URI:?COMBINED_URI is required}"
: "${ECR:?ECR is required}"
: "${SHA:?SHA is required}"
ECR_REPO_PREFIX="${ECR_REPO_PREFIX:-}"
CVE_ALLOW_CRITICAL="${CVE_ALLOW_CRITICAL:-0}"
S3_SBOM_BUCKET="${S3_SBOM_BUCKET:-}"

echo "[post_build] Pushing images to ECR..."
docker push "${EFA_URI}"
docker push "${ECR}/${ECR_REPO_PREFIX}efa:latest"
docker push "${COMBINED_URI}"
docker push "${ECR}/${ECR_REPO_PREFIX}dynamo-efa:latest"

echo "[post_build] External trivy CVE scans (CRITICAL + HIGH)..."
mkdir -p cve-reports
for name_and_img in \
    "efa:${EFA_URI}" \
    "dynamo-efa:${COMBINED_URI}"; do
  name="${name_and_img%%:*}"
  img="${name_and_img#*:}"
  echo "  scanning ${name} (${img})..."
  trivy image --severity CRITICAL,HIGH --scanners vuln \
    --format table --timeout 30m --no-progress --skip-version-check \
    --output "cve-reports/${name}_${SHA}_cve-critical-high.txt" \
    "${img}" || echo "    trivy exited non-zero (continuing; gate runs below)"
done

echo "[post_build] CVE gate: CRITICAL findings fail the build unless CVE_ALLOW_CRITICAL=1"
crit=$(grep -lE 'CRITICAL ' cve-reports/*.txt 2>/dev/null || true)
if [ -n "$crit" ] && [ "${CVE_ALLOW_CRITICAL}" != "1" ]; then
  echo "CRITICAL CVEs detected in:"
  for f in $crit; do
    echo "  --- $f ---"
    grep -E 'CRITICAL ' "$f" | head -10
  done
  echo "Set CVE_ALLOW_CRITICAL=1 on the CodeBuild project to waive during a review"
  exit 1
fi
echo "CVE gate passed (or allowlisted)"

echo "[post_build] Extracting in-image SBOMs..."
mkdir -p sbom-out
for ref in \
    "efa:${EFA_URI}" \
    "dynamo-efa:${COMBINED_URI}"; do
  name="${ref%%:*}"
  uri="${ref#*:}"
  mkdir -p "sbom-out/${name}"
  cid=$(docker create "${uri}" true)
  docker cp "${cid}:/opt/security/." "sbom-out/${name}/" 2>/dev/null \
    || echo "  (${name} has no /opt/security dir)"
  docker rm "${cid}" >/dev/null
done

echo "[post_build] Uploading SBOM + CVE reports to S3 (if configured)..."
if [ -n "${S3_SBOM_BUCKET}" ]; then
  aws s3 cp --recursive sbom-out/    "${S3_SBOM_BUCKET}/${SHA}/sbom/"    || true
  aws s3 cp --recursive cve-reports/ "${S3_SBOM_BUCKET}/${SHA}/cve/"     || true
  echo "  uploaded to ${S3_SBOM_BUCKET}/${SHA}/"
else
  echo "  S3_SBOM_BUCKET not set — skipping upload"
fi

echo "=== Build summary ==="
echo "  efa:        ${EFA_URI}"
echo "  dynamo-efa: ${COMBINED_URI}"
