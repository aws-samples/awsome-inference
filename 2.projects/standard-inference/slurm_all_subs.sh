#!/bin/bash

all_subjects=('biology' 'business' 'chemistry' 'computer science' 'economics' 'engineering' 'health' 'history' 'law' 'math' 'other' 'philosophy' 'physics' 'psychology')

for file in "${all_subjects[@]}"; do
    sbatch --job-name="$file" slurm_local.sh $file 
done
