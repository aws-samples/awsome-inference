#!/usr/bin/env bash
# Schedule a pod that requests one MIG slice and verifies nvidia-smi sees it.
# Also prints the full partition map on the node.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

log "Configuring kubectl for $CLUSTER_NAME in $AWS_REGION"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

node=$(kubectl get nodes -l node-type=g7e-mig -o jsonpath='{.items[0].metadata.name}')
log "Target node: $node"

# Discover the first nvidia.com/mig-* resource the node advertises.
resource=$(kubectl get node "$node" -o json | \
  jq -r '.status.allocatable | to_entries[] | select(.key | startswith("nvidia.com/mig-")) | .key' | head -n1)
if [[ -z "$resource" ]]; then
  echo "No nvidia.com/mig-* resources advertised on $node. Did 03-apply-mig-config.sh succeed?" >&2
  exit 1
fi
log "Will request one of: $resource"

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: mig-smoke-test
  labels:
    app: mig-smoke-test
spec:
  restartPolicy: Never
  tolerations:
    - key: nvidia.com/gpu
      operator: Equal
      value: "true"
      effect: NoSchedule
  nodeSelector:
    node-type: g7e-mig
  containers:
    - name: cuda
      image: nvcr.io/nvidia/cuda:12.6.2-base-ubuntu22.04
      command: ["bash","-lc","nvidia-smi && nvidia-smi -L && sleep 2"]
      resources:
        limits:
          ${resource}: "1"
YAML

log "Waiting for pod to reach Succeeded or Failed"
kubectl wait --for=condition=Ready pod/mig-smoke-test --timeout=5m 2>/dev/null || true
# Container is short-lived — tail logs once it terminates.
for _ in $(seq 1 30); do
  phase=$(kubectl get pod mig-smoke-test -o jsonpath='{.status.phase}')
  [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
  sleep 5
done

log "--- pod logs (mig-smoke-test) ---"
kubectl logs mig-smoke-test || true

log "--- node allocatable (nvidia.com/*) ---"
kubectl get node "$node" -o json | jq '.status.allocatable | with_entries(select(.key | startswith("nvidia.com/")))'

log "--- host-side nvidia-smi from the driver daemonset ---"
driver_pod=$(kubectl get pod -n "$GPU_OPERATOR_NAMESPACE" -l app=nvidia-driver-daemonset \
  --field-selector spec.nodeName="$node" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$driver_pod" ]]; then
  kubectl exec -n "$GPU_OPERATOR_NAMESPACE" "$driver_pod" -- nvidia-smi -L || true
  kubectl exec -n "$GPU_OPERATOR_NAMESPACE" "$driver_pod" -- nvidia-smi mig -lgi || true
fi

log "Cleanup:  kubectl delete pod mig-smoke-test"
