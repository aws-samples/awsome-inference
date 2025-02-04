#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=1 # number of nodes to use
#SBATCH --job-name=$1 # name of your job
#SBATCH --exclusive # job has exclusive use of the resource, no sharing
#SBATCH --gpus=1
#SBATCH --export=all

save_dir="eval_results/"
global_record_file="eval_results/eval_record_collection.csv"
model="meta-llama/Llama-2-7b-hf"
selected_subjects=$1
gpu_util=0.8

source activate std-inf

srun python evaluate_from_local.py \
                 --selected_subjects $selected_subjects \
                 --save_dir $save_dir \
                 --model $model \
                 --global_record_file $global_record_file \
                 --gpu_util $gpu_util
