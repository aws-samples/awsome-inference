#!/usr/bin/env bash
# Tear everything down: smoke-test pod, helm release, and the EKS nodegroup.
# This stops g7e.2xlarge on-demand billing. Safe to rerun.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

log "Configuring kubectl for $CLUSTER_NAME in $AWS_REGION"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null || true

log "Deleting smoke-test pod (if any)"
kubectl delete pod mig-smoke-test --ignore-not-found

log "Uninstalling helm release $GPU_OPERATOR_RELEASE"
helm uninstall "$GPU_OPERATOR_RELEASE" -n "$GPU_OPERATOR_NAMESPACE" 2>/dev/null || true
kubectl delete namespace "$GPU_OPERATOR_NAMESPACE" --ignore-not-found

log "Deleting nodegroup $NODEGROUP_NAME (this is what stops the billing)"
aws eks delete-nodegroup \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP_NAME" >/dev/null 2>&1 || \
  log "Nodegroup $NODEGROUP_NAME not found (already deleted?)"

log "Waiting for nodegroup deletion to complete"
aws eks wait nodegroup-deleted \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP_NAME" 2>/dev/null || true

log "Verify no g7e instances remain:"
aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
            "Name=instance-type,Values=g7e.*" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output table

# Optionally delete scratch subnets you created to add AZ coverage for g7e capacity.
# Opt-in via EXTRA_SUBNETS="subnet-aaa,subnet-bbb" — the script will try to
# disassociate each from its route table and delete the subnet.
if [[ -n "${EXTRA_SUBNETS:-}" ]]; then
  log "Cleaning up scratch subnets: $EXTRA_SUBNETS"
  IFS=',' read -r -a extras <<<"$EXTRA_SUBNETS"
  for s in "${extras[@]}"; do
    # Find any route table associations for this subnet and drop them.
    assoc_ids=$(aws ec2 describe-route-tables --region "$AWS_REGION" \
      --filters "Name=association.subnet-id,Values=$s" \
      --query 'RouteTables[].Associations[?SubnetId==`'"$s"'`].RouteTableAssociationId' \
      --output text 2>/dev/null || true)
    for a in $assoc_ids; do
      log "  disassociating $a from $s"
      aws ec2 disassociate-route-table --region "$AWS_REGION" --association-id "$a" >/dev/null 2>&1 || true
    done
    log "  deleting subnet $s"
    aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "$s" 2>&1 || \
      log "  (delete-subnet failed for $s — it may still have ENIs attached; retry in a minute)"
  done
fi

log "Done."
