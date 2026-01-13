#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=vllm-ep-multi-node-1rack
#SBATCH --nodes=18
#SBATCH --ntasks-per-node=1 
#SBATCH --output logs_multi_node_1rack/%x_%j.out
#SBATCH --error logs_multi_node_1rack/%x_%j.err
#SBATCH --exclusive=topo
#SBATCH --wait-all-nodes=1

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

set -x

mkdir -p logs_multi_node_1rack

###########################
###### User Variables #####
###########################

# default variables for Enroot
: "${APPS_PATH:=/fsx}"
: "${IMAGE:=$APPS_PATH/ubuntu/vLLM-testing/vllm-ep.sqsh}"
: "${HF_HOME:=/fsx/ubuntu/.cache/huggingface}"

## Set libfabric flags to use EFA
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1 
export FI_EFA_FORK_SAFE=1

## Set vLLM Environment Variables
export VLLM_ALL2ALL_BACKEND=pplx
export VLLM_USE_DEEP_GEMM=1
export VLLM_ENGINE_ITERATION_TIMEOUT_S=300
export VLLM_RPC_TIMEOUT=60000
export HF_TOKEN=$HF_TOKEN

## Set this flag for debugging EFA
# export FI_LOG_LEVEL=warn

## NCCL Environment variables
# export NCCL_DEBUG=INFO

# Model
# export MODEL="deepseek-ai/deepseek-moe-16b-base"
export MODEL_NAME="/fsx/ubuntu/.cache/huggingface/hub/models--deepseek-ai--deepseek-moe-16b-base/snapshots/521d2bc4fb69a3f3ae565310fcc3b65f97af2580"
export TP=1
export DP_TOTAL=72  # Total DP size across all nodes
export DP_NODE=4    # Local DP size per node

# Get primary node IP
export PRIMARY_NODE=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n1)
export PRIMARY_IP=$(srun --nodes=1 --ntasks=1 -w $PRIMARY_NODE hostname -I | awk '{print $1}')
export PORT=13345
echo "Primary node: $PRIMARY_NODE ($PRIMARY_IP)"
echo "Total nodes: 18 (72 GPUs)"

declare -a ARGS=(
    --container-image $IMAGE
    --container-mount-home
    --container-mounts /fsx/ubuntu/vLLM-testing:/workspace
    --container-mounts /dev/urandom:/dev/urandom
    --container-mounts $(pwd)/logs_multi_node_1rack:/logs_multi_node_1rack 
    --container-env HF_TOKEN
    --container-env VLLM_ALL2ALL_BACKEND
    --container-env VLLM_USE_DEEP_GEMM
    --container-env VLLM_ENGINE_ITERATION_TIMEOUT_S
    --container-env VLLM_RPC_TIMEOUT
    --container-env TP
    --container-env DP_TOTAL
    --container-env DP_NODE
    --container-env MODEL_NAME
    --container-env PRIMARY_IP
    --container-env PORT

)

srun -l --mpi=pmix --cpu-bind=none "${ARGS[@]}" \
    bash -c 'set -x;
    [ "$SLURM_PROCID" -eq 0 ] && EXTRA_FLAGS="--host 0.0.0.0 --port 8000 --api-server-count 4" || EXTRA_FLAGS="--headless --data-parallel-start-rank $((4 * SLURM_PROCID))";

    # Start vLLM server
    vllm serve $MODEL_NAME \
        $EXTRA_FLAGS \
        --trust-remote-code \
        --enable-expert-parallel \
        --data-parallel-size $DP_TOTAL \
        --data-parallel-size-local $DP_NODE \
        --data-parallel-address $PRIMARY_IP \
        --data-parallel-rpc-port $PORT &
    
    # Only run benchmarks on primary node
    if [ "$SLURM_PROCID" -eq 0 ]; then
        # Wait for server to be ready
        for i in {1..600}; do
            if curl -s http://localhost:8000/v1/models > /dev/null 2>&1; then
                echo "Primary server responding, starting benchmarks..."
                break
            fi
            sleep 5
        done
    
        # Run benchmarks
        mkdir -p logs_multi_node_1rack
        declare -a ISL_OSL_PAIRS=("128 128" "128 2048" "500 2000")
        for pair in "${ISL_OSL_PAIRS[@]}"; do
            read -r isl osl <<< "$pair"
            echo "Testing ISL=$isl, OSL=$osl"

            vllm bench serve \
                --model $MODEL_NAME \
                --dataset-name random \
                --random-input-len $isl \
                --random-output-len $osl \
                --num-prompts 100 \
                --ignore-eos \
                --trust-remote-code \
                > /logs_multi_node_1rack/bench_${isl}_${osl}_${SLURM_JOB_ID}.log 2>&1 &
        done
        wait
    else
        # Worker nodes just wait
        wait
    fi
    '
