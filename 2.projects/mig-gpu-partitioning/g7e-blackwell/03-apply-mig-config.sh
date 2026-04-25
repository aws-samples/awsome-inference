#!/usr/bin/env bash
# Ask mig-manager to enable MIG on the g7e node and apply a partition profile.
#
# Blackwell RTX PRO 6000 Server Edition supports MIG with up to 4 GPU instances
# per physical GPU (different granularity than A100's 7). Valid profiles depend on
# the exact SKU & driver; query with `nvidia-smi mig -lgip` after the operator is up
# (see: kubectl exec -n gpu-operator <nvidia-driver-daemonset-...> -- nvidia-smi mig -lgip).
#
# Default profile: `all-1g.24gb` — 4 equal partitions, ~24 GiB each on the 96 GiB
# RTX PRO 6000 Server Edition SKU that ships in g7e. Valid alternatives for this
# SKU include `all-2g.48gb` (2 partitions), `all-4g.96gb` (1 MIG partition covering
# the whole GPU), and `all-disabled`.
# Override with: MIG_PROFILE=all-2g.48gb ./03-apply-mig-config.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

MIG_PROFILE="${MIG_PROFILE:-all-1g.24gb}"

log "Configuring kubectl for $CLUSTER_NAME in $AWS_REGION"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

node=$(kubectl get nodes -l node-type=g7e-mig -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$node" ]]; then
  echo "No node with label node-type=g7e-mig found" >&2
  exit 1
fi
log "Target node: $node"

log "Available MIG profiles (from mig-parted configmap):"
kubectl get configmap -n "$GPU_OPERATOR_NAMESPACE" default-mig-parted-config \
  -o jsonpath='{.data.config\.yaml}' 2>/dev/null | \
  grep -E '^\s{2}[a-zA-Z0-9._-]+:\s*$' | sed 's/^/  /' || \
  log "(configmap not yet present — operator may still be bootstrapping)"

log "Labeling $node with nvidia.com/mig.config=$MIG_PROFILE"
kubectl label node "$node" "nvidia.com/mig.config=$MIG_PROFILE" --overwrite

log "Watching mig.config.state (expect: pending -> rebooting (if needed) -> success)"
# mig-manager may reboot the node, which pauses the watch. Poll with a timeout.
deadline=$(( $(date +%s) + 20*60 ))
last_state=""
while [[ $(date +%s) -lt $deadline ]]; do
  state=$(kubectl get node "$node" \
    -o jsonpath='{.metadata.labels.nvidia\.com/mig\.config\.state}' 2>/dev/null || true)
  if [[ "$state" != "$last_state" ]]; then
    log "mig.config.state=$state"
    last_state="$state"
  fi
  case "$state" in
    success) break ;;
    failed)  echo "mig-manager reported FAILED — inspect: kubectl logs -n $GPU_OPERATOR_NAMESPACE -l app=nvidia-mig-manager" >&2; exit 1 ;;
  esac
  sleep 10
done

if [[ "$last_state" != "success" ]]; then
  echo "Timed out waiting for mig.config.state=success (last=$last_state)" >&2
  exit 1
fi

log "MIG partitioning done. Advertised GPU resources on the node:"
kubectl get node "$node" -o json | jq '.status.allocatable | with_entries(select(.key | startswith("nvidia.com/")))'

log "Next: run ./04-test-mig.sh to schedule a pod onto a MIG slice."
