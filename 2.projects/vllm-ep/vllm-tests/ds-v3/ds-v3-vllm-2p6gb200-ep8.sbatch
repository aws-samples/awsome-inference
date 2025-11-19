#!/bin/bash
#SBATCH --job-name=ds-vllm
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1

set -x

export MODEL_NAME=deepseek-ai/DeepSeek-V3-0324
export MODEL_PATH=`python -c "from pathlib import Path; from huggingface_hub import hf_hub_download; print(Path(hf_hub_download('$MODEL_NAME', filename='config.json')).parent)"`

export MASTER_IP=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)
export PORT=13579

export VLLM_ALL2ALL_BACKEND=pplx 
export VLLM_USE_DEEP_GEMM=1

srun -l \
    --mpi=pmix --cpu-bind=none \
    --container-image /fsx/ubuntu/belevich/vllm-ep/vllm-ep-nvshmem-aws-2.sqsh \
    --container-mounts=${HF_HOME}:${HF_HOME} \
    bash -c 'set -x; 
    [ "$SLURM_PROCID" -eq 0 ] && EXTRA_FLAGS="" || EXTRA_FLAGS="--headless --data-parallel-start-rank $((4 * SLURM_PROCID))";
vllm serve $MODEL_PATH \
    $EXTRA_FLAGS \
    --port 8000 \
    --served-model-name $MODEL_NAME \
    --trust-remote-code \
    --data-parallel-size 8 \
    --data-parallel-size-local 4 \
    --data-parallel-address $MASTER_IP \
    --data-parallel-rpc-port $PORT \
    --enable-expert-parallel
