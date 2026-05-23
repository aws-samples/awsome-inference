#!/bin/bash
# Round 7 — config matrix runner.
# Iterates through 9 Dynamo configs, deploys each, tests /v1/models +
# /v1/completions, captures pod state, tears down before the next one.
#
# Each test takes ~5-8 min: deploy (1 min) + Ready (2-4 min cold model load) +
# 2 curls (10s) + teardown (30s).
#
# Usage:
#   IMAGE_TAG=520cfc584abb ./run-matrix.sh
set -uo pipefail

: "${IMAGE_TAG:=520cfc584abb}"
ECR=${ECR_REGISTRY}
EVIDENCE_ROOT=/home/ubuntu/awesome-inferencing/docs/evidence/rev8-pr72-e2e-2026-05-21/round7-config-matrix
BASE_VLLM=/tmp/awsome-inference-1/2.projects/dynamo-inference/k8s/dgd-dynamo-combined-vllm.yaml
BASE_TRTLLM=/tmp/awsome-inference-1/2.projects/dynamo-inference/k8s/dgd-dynamo-combined-trtllm.yaml
NS=default

# Each config tuple: name|base|patch_type|description
# patch_type controls which sed transform we apply to the base manifest:
#   kv_router_agg     — adds DYN_ROUTER_MODE=kv + --kv-events-config to existing prefill+decode (treats as 2-replica router)
#   kv_router_disagg  — same + replicas=2 on both
#   kvbm              — replaces --kv-transfer-config with kvbm flavor + adds DYN_KVBM_CPU_CACHE_GB
#   trtllm_baseline   — TRT-LLM baseline (uses trtllm DGD)
#   trtllm_router     — TRT-LLM with DYN_ROUTER_MODE=kv
#   sglang_*          — would need sglang DGD (skipped if not present)

CONFIGS=(
  "vllm-agg-router|$BASE_VLLM|kv_router_agg|vLLM aggregated + KV router"
  "vllm-disagg-router|$BASE_VLLM|kv_router_disagg|vLLM disaggregated + KV router (cross-node)"
  "vllm-disagg-kvbm|$BASE_VLLM|kvbm|vLLM disaggregated + KVBM multi-tier cache"
  "trtllm-disagg|$BASE_TRTLLM|trtllm_baseline|TRT-LLM disaggregated baseline"
  "trtllm-disagg-router|$BASE_TRTLLM|trtllm_router|TRT-LLM disaggregated + KV router"
)

mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/SUMMARY.md"
{
  echo "# Round 7 — Dynamo config matrix on rev8 image"
  echo
  echo "**Image:** \`${ECR}/dynamo-efa:${IMAGE_TAG}\`"
  echo "**Cluster:** P5.48xlarge HyperPod (2 nodes)"
  echo
  echo "| Config | Backend | Features | Pods Ready | /v1/models | /v1/completions | Time |"
  echo "|---|---|---|---|---|---|---|"
} > "$SUMMARY"

apply_patch() {
  local base="$1" type="$2" out="$3" cfg_name="$4"
  # 1. Substitute image SHA
  sed "s|dynamo-efa:9467d1460c71|dynamo-efa:${IMAGE_TAG}|g" "$base" > "$out"
  # 2. Rename DGD so multiple configs don't collide
  sed -i "s|name: dynamo-combined-vllm|name: ${cfg_name}|g; s|app.kubernetes.io/part-of: dynamo-combined-vllm|app.kubernetes.io/part-of: ${cfg_name}|g; s|values: \[dynamo-combined-vllm\]|values: [${cfg_name}]|g" "$out"
  sed -i "s|name: dynamo-combined-trtllm|name: ${cfg_name}|g; s|app.kubernetes.io/part-of: dynamo-combined-trtllm|app.kubernetes.io/part-of: ${cfg_name}|g; s|values: \[dynamo-combined-trtllm\]|values: [${cfg_name}]|g" "$out"

  case "$type" in
    kv_router_agg|kv_router_disagg|trtllm_router)
      # Insert DYN_ROUTER_MODE=kv into both Prefill+Decode envs (under existing - { name: DYNAMO_BACKEND, ...} block)
      python3 -c "
import sys
text = open('$out').read()
inject = '''        - { name: DYN_ROUTER_MODE,           value: \"kv\" }
'''
text = text.replace('        - { name: DYNAMO_BACKEND,             value: \"vllm\" }\n        - { name: ETCD_ENDPOINTS',
                    '        - { name: DYNAMO_BACKEND,             value: \"vllm\" }\n' + inject + '        - { name: ETCD_ENDPOINTS', 1)
text = text.replace('        - { name: DYNAMO_BACKEND,             value: \"trtllm\" }\n        - { name: ETCD_ENDPOINTS',
                    '        - { name: DYNAMO_BACKEND,             value: \"trtllm\" }\n' + inject + '        - { name: ETCD_ENDPOINTS', 1)
open('$out','w').write(text)
"
      ;;
    kvbm)
      # Replace LIBFABRIC kv-transfer-config with KVBM-style + add DYN_KVBM_CPU_CACHE_GB env
      python3 -c "
import re
text = open('$out').read()
# Drop the kv_connector_extra_config (KVBM doesn't need it)
text = re.sub(r'--kv-transfer-config[^\n]*\\\\\n', '--kv-transfer-config \\'{\"kv_connector\":\"NixlConnector\",\"kv_role\":\"kv_both\"}\\' \\\\\n', text)
# Add DYN_KVBM_CPU_CACHE_GB env to PrefillWorker + DecodeWorker
inject = '        - { name: DYN_KVBM_CPU_CACHE_GB,     value: \"50\" }\n'
text = text.replace('        - { name: HF_HOME,                    value: \"/shared/hf_cache\" }',
                    inject + '        - { name: HF_HOME,                    value: \"/shared/hf_cache\" }')
open('$out','w').write(text)
"
      ;;
    trtllm_baseline)
      : # No additional patch; trtllm DGD as-is
      ;;
  esac
}

run_test() {
  local cfg="$1" desc="$2" yaml="$3"
  local d="$EVIDENCE_ROOT/$cfg"
  mkdir -p "$d"
  cp "$yaml" "$d/dgd.yaml"

  echo ""
  echo "============================================================"
  echo "### Test: $cfg"
  echo "### Description: $desc"
  echo "============================================================"

  local t_start=$(date +%s)

  kubectl apply -f "$yaml" > "$d/01-apply.log" 2>&1 || { echo "APPLY FAILED"; return 1; }

  echo "Waiting for pods Ready (up to 12 min)..."
  local ready=0
  for i in $(seq 1 72); do
    local pods=$(kubectl get pods -n $NS -l "app.kubernetes.io/part-of=$cfg" -o jsonpath='{range .items[*]}{.metadata.name}={.status.phase}/{.status.containerStatuses[0].ready};{end}' 2>/dev/null)
    local rdy=$(echo "$pods" | tr ';' '\n' | grep -c "=Running/true")
    local tot=$(echo "$pods" | tr ';' '\n' | grep -c "=")
    echo "  $(date -u +%H:%M:%SZ) ready=$rdy/$tot $pods" >> "$d/02-wait.log"
    if [ "$rdy" -ge 3 ] && [ "$rdy" = "$tot" ]; then ready=1; break; fi
    sleep 10
  done

  kubectl get pods -n $NS -l "app.kubernetes.io/part-of=$cfg" -o wide > "$d/03-pods.txt" 2>&1

  local svc_ip=$(kubectl get svc -n $NS -l "app.kubernetes.io/part-of=$cfg" -o jsonpath='{.items[?(@.spec.ports[0].port==8000)].spec.clusterIP}' 2>/dev/null | head -c 32)
  local models="N/A" comp="N/A" http="N/A"
  local t_test_start=$(date +%s)

  if [ "$ready" = "1" ] && [ -n "$svc_ip" ]; then
    kubectl run "tester-$cfg" --rm -i --restart=Never --image=curlimages/curl:latest -n $NS --quiet -- \
      curl -sS http://$svc_ip:8000/v1/models > "$d/04-models.json" 2>&1
    if grep -q '"id"' "$d/04-models.json"; then
      models="PASS"
      local model=$(python3 -c "import json,sys; print(json.load(open('$d/04-models.json'))['data'][0]['id'])" 2>/dev/null)
      kubectl run "tester2-$cfg" --rm -i --restart=Never --image=curlimages/curl:latest -n $NS --quiet -- \
        curl -sS -X POST http://$svc_ip:8000/v1/completions \
          -H "Content-Type: application/json" \
          -d "{\"model\":\"$model\",\"prompt\":\"The capital of France is\",\"max_tokens\":20,\"temperature\":0}" \
          -w "\nHTTP=%{http_code}\n" > "$d/05-completion.json" 2>&1
      http=$(grep "^HTTP=" "$d/05-completion.json" | head -1 | cut -d= -f2)
      if [ "$http" = "200" ] && grep -q '"text"' "$d/05-completion.json"; then
        comp="PASS"
      else
        comp="FAIL"
      fi
    else
      models="FAIL"
    fi
  else
    models="POD-NOT-READY"
  fi

  local t_end=$(date +%s)
  local elapsed=$((t_end - t_start))
  echo "  [${cfg}] models=$models completions=$comp http=$http elapsed=${elapsed}s"
  echo "| $cfg | ${desc%% *} | $desc | $ready/3 | $models | $comp ($http) | ${elapsed}s |" >> "$SUMMARY"

  # Teardown
  kubectl delete -f "$yaml" --wait=false --ignore-not-found=true > "$d/06-teardown.log" 2>&1
  # Wait for pods to drain so next config can claim resources
  for i in $(seq 1 30); do
    local n=$(kubectl get pods -n $NS -l "app.kubernetes.io/part-of=$cfg" 2>/dev/null | tail -n +2 | wc -l)
    [ "$n" = "0" ] && break
    sleep 5
  done
}

for entry in "${CONFIGS[@]}"; do
  IFS='|' read -r name base type desc <<< "$entry"
  out="/tmp/dgd-${name}.yaml"
  apply_patch "$base" "$type" "$out" "$name"
  run_test "$name" "$desc" "$out" || echo "  ($name continuing despite failure)"
done

echo ""
echo "============================================================"
echo "Matrix complete. Summary at $SUMMARY"
echo "============================================================"
cat "$SUMMARY"
