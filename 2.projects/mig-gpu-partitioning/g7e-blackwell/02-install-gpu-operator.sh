#!/usr/bin/env bash
# Install the NVIDIA GPU Operator via Helm with MIG manager enabled (mixed strategy).
# The operator deploys the driver, container toolkit, device plugin, DCGM exporter,
# node feature discovery, and mig-manager. On Blackwell the operator picks the
# right driver automatically (open kernel modules / 570+ branch).
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

if ! command -v helm >/dev/null; then
  echo "helm is required but not installed" >&2
  exit 1
fi

log "Configuring kubectl for $CLUSTER_NAME in $AWS_REGION"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

log "Waiting for a Ready node with label node-type=g7e-mig"
for _ in $(seq 1 60); do
  ready=$(kubectl get nodes -l node-type=g7e-mig \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
    2>/dev/null | grep -c '^True$' || true)
  if [[ "$ready" -ge 1 ]]; then
    break
  fi
  sleep 10
done
kubectl get nodes -l node-type=g7e-mig -L node.kubernetes.io/instance-type

log "Adding NVIDIA helm repo and updating"
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
helm repo update >/dev/null

log "Installing gpu-operator into namespace $GPU_OPERATOR_NAMESPACE (release=$GPU_OPERATOR_RELEASE)"
# Key flags:
#   mig.strategy=mixed     -> expose differently-sized MIG partitions as distinct resources
#   migManager.default=all-disabled -> start with MIG off; we flip it on via the node label
#                                     once the operator is healthy (in 03-apply-mig-config.sh).
#   migManager.WITH_REBOOT=true -> let mig-manager reboot the node when required (Blackwell
#                                   often needs a reboot after the first MIG enable).
#   driver.enabled=true    -> install NVIDIA driver via the operator's driver container
#                             (the EKS-optimized NVIDIA AMI ships a driver, but the
#                              operator's driver container is what mig-manager is
#                              validated against; toolkit-only mode is flaky on Blackwell).
#
# If you prefer to keep the host driver (from the EKS AL2023 NVIDIA AMI) and skip the
# operator's driver container, override with DRIVER_ENABLED=false on the command line.
DRIVER_ENABLED="${DRIVER_ENABLED:-true}"

helm upgrade --install "$GPU_OPERATOR_RELEASE" nvidia/gpu-operator \
  --namespace "$GPU_OPERATOR_NAMESPACE" --create-namespace \
  --set mig.strategy=mixed \
  --set migManager.enabled=true \
  --set migManager.default=all-disabled \
  --set migManager.env[0].name=WITH_REBOOT \
  --set-string migManager.env[0].value="true" \
  --set driver.enabled="$DRIVER_ENABLED" \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true \
  --set dcgmExporter.enabled=true \
  --set nodeStatusExporter.enabled=true \
  --wait --timeout 20m

log "Operator install complete. Pods:"
kubectl get pods -n "$GPU_OPERATOR_NAMESPACE" -o wide

# ---------------------------------------------------------------------------
# AL2023 NVIDIA AMI ships containerd v3 with NO pre-configured `nvidia`
# runtime and no explicit SystemdCgroup setting, while the gpu-operator
# v26.x toolkit (nvcr.io/nvidia/k8s/container-toolkit:v1.19.0) generates a
# v2-style drop-in that doesn't carry SystemdCgroup=true. That mismatch causes
# EVERY gpu-operator pod on the node to crash with:
#     runc create failed: expected cgroupsPath to be of format
#     "slice:prefix:name" for systemd cgroups, got "/kubepods/..." instead
# and blocks nvidia-device-plugin from advertising nvidia.com/mig-* resources
# (it also takes aws-node down in the process, breaking pod networking).
#
# We paper over it by writing a correct v3 drop-in to
# /etc/containerd/conf.d/99-nvidia.toml (runc+nvidia, both with
# SystemdCgroup=true, nvidia BinaryName pointing at the toolkit-installed
# binary), then restarting containerd+kubelet. The existing config.toml on the
# AL2023 NVIDIA AMI already `imports = ["/etc/containerd/conf.d/*.toml"]`.
log "Applying AL2023+containerd-v3 runtime drop-in (needed for gpu-operator v26.x)"
node=$(kubectl get nodes -l node-type=g7e-mig -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$node" ]]; then
  echo "No g7e node found — cannot apply runtime fix" >&2
  exit 1
fi

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: containerd-runtime-fix
  namespace: default
spec:
  nodeName: $node
  hostPID: true
  hostNetwork: true
  restartPolicy: Never
  tolerations:
    - key: nvidia.com/gpu
      operator: Equal
      value: "true"
      effect: NoSchedule
  containers:
    - name: fix
      image: alpine:3.20
      securityContext:
        privileged: true
      command: ["/bin/sh","-c"]
      args:
        - |
          set -eu
          cat > /host/etc/containerd/conf.d/99-nvidia.toml <<'EOF'
          version = 3

          [plugins."io.containerd.cri.v1.runtime".containerd]
            default_runtime_name = "runc"

            [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc]
              runtime_type = "io.containerd.runc.v2"
              [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options]
                SystemdCgroup = true

            [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia]
              runtime_type = "io.containerd.runc.v2"
              [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia.options]
                BinaryName = "/usr/local/nvidia/toolkit/nvidia-container-runtime"
                SystemdCgroup = true
          EOF
          # Remove any stale drop-in nvidia-ctk wrote (v2 schema, wrong
          # BinaryName) before we bounce the daemons.
          rm -f /host/etc/containerd/conf.d/nvidia.toml
          chroot /host systemctl restart containerd
          chroot /host systemctl restart kubelet
          echo "runtime fix applied"
      volumeMounts:
        - name: host
          mountPath: /host
  volumes:
    - name: host
      hostPath:
        path: /
YAML

log "Waiting for fix pod to complete"
# kubelet restart on the same node makes the pod transition surprising; poll.
for _ in $(seq 1 30); do
  phase=$(kubectl get pod containerd-runtime-fix -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
  sleep 5
done
kubectl logs containerd-runtime-fix 2>&1 || true
kubectl delete pod containerd-runtime-fix --ignore-not-found >/dev/null

log "Waiting for nvidia-container-toolkit daemonset to report Ready on the node"
for _ in $(seq 1 60); do
  ready=$(kubectl -n "$GPU_OPERATOR_NAMESPACE" get pod \
    -l app=nvidia-container-toolkit-daemonset \
    --field-selector "spec.nodeName=$node" \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "")
  [[ "$ready" == "true" ]] && break
  sleep 5
done
kubectl -n "$GPU_OPERATOR_NAMESPACE" get pods --field-selector "spec.nodeName=$node" -o wide

log "Next: run ./03-apply-mig-config.sh to partition the GPU."
