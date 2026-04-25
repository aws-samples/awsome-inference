#!/usr/bin/env bash
# Create an EKS managed nodegroup with a single g7e.2xlarge instance
# (NVIDIA RTX PRO 6000 Blackwell Server Edition) and wait for it to become ACTIVE.
#
# WARNING: this starts an ON_DEMAND g7e.2xlarge — on-demand billing starts
# immediately. Run `./99-cleanup.sh` when done.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

log "Looking up VPC details for cluster $CLUSTER_NAME in $AWS_REGION"
cluster_json=$(aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME")
subnet_ids=$(echo "$cluster_json" | jq -r '.cluster.resourcesVpcConfig.subnetIds[]')

# Allow caller to pin a specific subnet set via SUBNETS="subnet-aaa,subnet-bbb".
# Useful when a given instance type has InsufficientInstanceCapacity in some AZs —
# g7e in particular is capacity-constrained and we saw us-west-2a return ICE.
private_subnets=()
if [[ -n "${SUBNETS:-}" ]]; then
  IFS=',' read -r -a private_subnets <<<"$SUBNETS"
  log "Using SUBNETS override: ${private_subnets[*]}"
else
  # Fall back to every private subnet (MapPublicIpOnLaunch=false) in the cluster VPC.
  for s in $subnet_ids; do
    is_public=$(aws ec2 describe-subnets --region "$AWS_REGION" --subnet-ids "$s" \
      --query 'Subnets[0].MapPublicIpOnLaunch' --output text)
    if [[ "$is_public" == "False" ]]; then
      private_subnets+=("$s")
    fi
  done
  log "Private subnets: ${private_subnets[*]}"
fi

# Reuse the IAM node role from the existing osmo-gpu-nodes nodegroup so we don't
# have to provision a new role / policies for this throwaway test.
log "Looking up an existing GPU nodegroup to copy its node IAM role"
existing_ng=$(aws eks list-nodegroups --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" \
  --query 'nodegroups[?contains(@, `gpu`)] | [0]' --output text)
if [[ -z "$existing_ng" || "$existing_ng" == "None" ]]; then
  echo "No existing GPU nodegroup found to copy node role from; aborting." >&2
  exit 1
fi
node_role=$(aws eks describe-nodegroup --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$existing_ng" --query 'nodegroup.nodeRole' --output text)
log "Reusing node role from $existing_ng: $node_role"

# Turn the label/taint env vars into CLI args.
labels_arg=$(python3 -c '
import os, json
pairs = [kv.split("=", 1) for kv in os.environ["NODE_LABELS"].split(",") if kv]
print(json.dumps(dict(pairs)))
')
taints_arg="$NODE_TAINTS_JSON"

log "Creating nodegroup $NODEGROUP_NAME (instance=$INSTANCE_TYPE, ami=$AMI_TYPE)"
aws eks create-nodegroup \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP_NAME" \
  --scaling-config "minSize=$MIN_SIZE,maxSize=$MAX_SIZE,desiredSize=$DESIRED_SIZE" \
  --disk-size "$DISK_SIZE" \
  --subnets "${private_subnets[@]}" \
  --instance-types "$INSTANCE_TYPE" \
  --ami-type "$AMI_TYPE" \
  --capacity-type "$CAPACITY_TYPE" \
  --node-role "$node_role" \
  --labels "$labels_arg" \
  --taints "$taints_arg" \
  --tags "project=g7e-mig-test,owner=$USER" \
  --output json >/dev/null

log "Waiting for nodegroup to become ACTIVE (this usually takes 3-5 minutes)..."
aws eks wait nodegroup-active \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP_NAME"

log "Nodegroup $NODEGROUP_NAME is ACTIVE. EC2 instance:"
aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
            "Name=tag:eks:nodegroup-name,Values=$NODEGROUP_NAME" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,PrivateIpAddress,State.Name]' \
  --output table

log "Configure kubectl, then:  kubectl get nodes -l node-type=g7e-mig"
