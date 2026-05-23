#!/usr/bin/env bash
# sbom.sh — extract and summarize the SBOM + CVE report from an image.
#
# Usage:
#   ./scripts/sbom.sh <image>                     # print summary
#   ./scripts/sbom.sh <image> <output-dir>        # copy artifacts to disk

set -euo pipefail

IMAGE="${1:-}"
OUT_DIR="${2:-}"

if [[ -z "$IMAGE" ]]; then
  cat >&2 <<EOF
Usage: $0 <image> [output-dir]

Examples:
  $0 efa-networking:v1
  $0 dynamo-combined-efa:v1 /tmp/sbom-dynamo
EOF
  exit 1
fi

CID=$(docker create "$IMAGE" 2>/dev/null)
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

echo "== /opt/security contents in $IMAGE =="
docker export "$CID" 2>/dev/null | tar -t 2>/dev/null | grep '^opt/security/' | sed 's|^opt/security/|  |' || {
  echo "(no /opt/security directory found; image may not be built with SBOM layer)"
  exit 2
}

if [[ -n "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  docker cp "$CID:/opt/security/." "$OUT_DIR/"
  echo ""
  echo "Copied to $OUT_DIR:"
  ls -la "$OUT_DIR"
  SCAN_TXT="$OUT_DIR/cve-report.txt"
  CRITICAL_TXT="$OUT_DIR/cve-critical.txt"
else
  # Stream into temp files for summary
  TMP=$(mktemp -d)
  docker cp "$CID:/opt/security/." "$TMP/" >/dev/null 2>&1 || true
  SCAN_TXT="$TMP/cve-report.txt"
  CRITICAL_TXT="$TMP/cve-critical.txt"
fi

echo ""
if [[ -s "$CRITICAL_TXT" ]]; then
  echo "== CVE summary (CRITICAL) =="
  CRIT=$(grep -c 'CRITICAL' "$CRITICAL_TXT" 2>/dev/null || echo 0)
  echo "CRITICAL CVE entries in cve-critical.txt: $CRIT"
fi

if [[ -s "$SCAN_TXT" ]]; then
  echo ""
  echo "== CVE summary (CRITICAL + HIGH) =="
  HIGH=$(grep -c 'HIGH' "$SCAN_TXT" 2>/dev/null || echo 0)
  CRIT=$(grep -c 'CRITICAL' "$SCAN_TXT" 2>/dev/null || echo 0)
  echo "HIGH  entries: $HIGH"
  echo "CRIT  entries: $CRIT"
fi

echo ""
echo "== Inspect SBOM =="
echo "  spdx-json:       $([[ -n "$OUT_DIR" ]] && echo "$OUT_DIR" || echo "$TMP")/sbom.spdx.json"
echo "  cyclonedx-json:  $([[ -n "$OUT_DIR" ]] && echo "$OUT_DIR" || echo "$TMP")/sbom.cyclonedx.json"
echo ""
echo "Tip: pipe through 'jq .packages' (SPDX) or 'jq .components' (CycloneDX)."
