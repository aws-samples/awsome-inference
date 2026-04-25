#!/usr/bin/env bash
# Shared environment variables for the g7e (RTX PRO 6000 Blackwell) MIG test scripts.
# Source this file from each step script: `source ./env.sh`

# NOTE on AWS_REGION: because of the default-if-unset (:-) syntax below, if your shell
# already exports AWS_REGION to something else (e.g. us-east-1), that value wins and
# the scripts will try to talk to the cluster in the wrong region. Either
# `unset AWS_REGION` before running, or prefix each command with AWS_REGION=us-west-2.
export AWS_REGION="${AWS_REGION:-us-west-2}"
export CLUSTER_NAME="${CLUSTER_NAME:-osmo}"

# Optional AZ pinning: comma-separated list of subnet IDs passed to
# `aws eks create-nodegroup --subnets`. Useful when g7e has ICE in some AZs
# (see README "Capacity" section). When unset, the script falls back to every
# private subnet it can find in the cluster VPC.
#   e.g. export SUBNETS=subnet-0abc,subnet-0def
# export SUBNETS=

# g7e.2xlarge = 1 x NVIDIA RTX PRO 6000 Blackwell Server Edition, 8 vCPU, 32 GiB.
# Smallest g7e size, sufficient to exercise MIG partitioning on a single GPU.
export INSTANCE_TYPE="${INSTANCE_TYPE:-g7e.2xlarge}"
export NODEGROUP_NAME="${NODEGROUP_NAME:-g7e-mig-test}"

# AL2023 NVIDIA is the recommended path for new GPU node groups on EKS 1.30+.
# AMI_TYPE=AL2023_x86_64_NVIDIA picks the latest EKS-optimized Blackwell-capable image.
export AMI_TYPE="${AMI_TYPE:-AL2023_x86_64_NVIDIA}"

export DISK_SIZE="${DISK_SIZE:-100}"
export CAPACITY_TYPE="${CAPACITY_TYPE:-ON_DEMAND}"
export DESIRED_SIZE="${DESIRED_SIZE:-1}"
export MIN_SIZE="${MIN_SIZE:-0}"
export MAX_SIZE="${MAX_SIZE:-1}"

# MIG-specific node labels. The NVIDIA GPU operator's mig-manager watches
# `nvidia.com/mig.config` and (re)partitions the GPU when the value changes.
export NODE_LABELS="node-type=g7e-mig,nvidia.com/mig.config=all-disabled"

# Taint keeps non-GPU workloads off this node. Pods must tolerate
# nvidia.com/gpu=true:NoSchedule to land here.
export NODE_TAINTS_JSON='[{"key":"nvidia.com/gpu","value":"true","effect":"NO_SCHEDULE"}]'

# Helm release name & namespace for the NVIDIA GPU operator.
export GPU_OPERATOR_NAMESPACE="${GPU_OPERATOR_NAMESPACE:-gpu-operator}"
export GPU_OPERATOR_RELEASE="${GPU_OPERATOR_RELEASE:-gpu-operator}"
