#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=vllm-ep-single-node
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1 
#SBATCH --output logs_single_node/%x_%j.out
#SBATCH --error logs_single_node/%x_%j.err
#SBATCH --exclusive=topo
#SBATCH --wait-all-nodes=1

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

mkdir -p logs_single_node

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
export HF_TOKEN=$HF_TOKEN

## Set this flag for debugging EFA
export FI_LOG_LEVEL=warn

## NCCL Environment variables
export NCCL_DEBUG=INFO

declare -a ARGS=(
    --container-image $IMAGE
    --container-mount-home
    --container-mounts /fsx/ubuntu/vLLM-testing:/workspace
    --container-env HF_TOKEN
    --container-env VLLM_ALL2ALL_BACKEND
    --container-env VLLM_USE_DEEP_GEMM
)

# Start vLLM server and run benchmarks in single srun
echo "Starting vLLM server and benchmarks..."
srun "${ARGS[@]}" bash -c "
    cd /workspace

    # ISL/OSL combinations to test
    declare -a ISL_OSL_PAIRS=(
        \"128 128\"
        \"128 2048\"
        \"128 4096\"
        \"500 2000\"
        \"1024 2048\"
        \"2048 128\"
        \"2048 2048\"
        \"5000 500\"
        \"20000 2000\"
    )

    # Model
    export MODEL=\"deepseek-ai/deepseek-moe-16b-base\"
    export TP=1
    export DP=4

    # Start server in background
    vllm serve \$MODEL \
        --trust-remote-code \
        --tensor-parallel-size \$TP \
        --data-parallel-size \$DP \
        --enable-expert-parallel \
        --host 0.0.0.0 \
        --port 8000 &
    
    SERVER_PID=\$!
    # Wait for server
    for i in {1..120}; do
        if curl -s http://localhost:8000/v1/models > /dev/null 2>&1; then
            echo 'Server ready'
            break
        fi
        sleep 5
    done

    # Run benchmarks
    for pair in \"\${ISL_OSL_PAIRS[@]}\"; do
        read -r isl osl <<< \"\$pair\"
        echo \"Testing ISL=\$isl, OSL=\$osl\"
        
        vllm bench serve \
            --model \$MODEL \
            --dataset-name random \
            --random-input-len \$isl \
            --random-output-len \$osl \
            --num-prompts 1000 \
            --ignore-eos \
            --trust-remote-code \
            > logs_single_node/results_\${isl}_\${osl}_${SLURM_JOB_ID}.txt 2>&1
    done
    
    # Cleanup
    kill \$SERVER_PID
"
