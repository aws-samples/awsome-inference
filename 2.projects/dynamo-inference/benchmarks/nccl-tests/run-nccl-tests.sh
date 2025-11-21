#!/bin/bash

# NCCL All-Reduce and All-Gather Test Runner
# This script runs comprehensive NCCL collective operation tests
# Optimized for AWS with EFA support

set -e

# Configuration
NUM_GPUS=${NUM_GPUS:-8}
MIN_SIZE=${MIN_SIZE:-$((1024*1024))}        # 1 MB
MAX_SIZE=${MAX_SIZE:-$((8*1024*1024*1024))} # 8 GB
WARMUP_ITERS=${WARMUP_ITERS:-5}
ITERS=${ITERS:-20}

# NCCL Environment Variables
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export NCCL_DEBUG_SUBSYS=${NCCL_DEBUG_SUBSYS:-INIT,COLL}
export NCCL_IB_DISABLE=0
export NCCL_SOCKET_IFNAME=ens

# EFA-specific optimizations
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_TREE_THRESHOLD=4294967296
export NCCL_PROTO=Simple

# Performance tuning
export NCCL_BUFFSIZE=2097152
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0

# Check if nccl-tests is available
if ! command -v all_reduce_perf &> /dev/null; then
    echo "Error: NCCL tests not found. Please install nccl-tests."
    echo "Installation: git clone https://github.com/NVIDIA/nccl-tests.git && cd nccl-tests && make MPI=1"
    exit 1
fi

# Create results directory
RESULTS_DIR="nccl_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "=========================================="
echo "NCCL Collective Operations Benchmark"
echo "=========================================="
echo "GPUs: $NUM_GPUS"
echo "Message Size Range: $MIN_SIZE to $MAX_SIZE bytes"
echo "Warmup Iterations: $WARMUP_ITERS"
echo "Test Iterations: $ITERS"
echo "Results Directory: $RESULTS_DIR"
echo "=========================================="
echo ""

# Function to run NCCL test
run_nccl_test() {
    local test_name=$1
    local test_binary=$2
    local output_file="$RESULTS_DIR/${test_name}_$(date +%Y%m%d_%H%M%S).txt"

    echo "Running $test_name test..."
    echo "Output: $output_file"

    # Run the test
    $test_binary \
        -b $MIN_SIZE \
        -e $MAX_SIZE \
        -f 2 \
        -g $NUM_GPUS \
        -w $WARMUP_ITERS \
        -n $ITERS \
        -c 1 \
        2>&1 | tee "$output_file"

    echo "$test_name test completed."
    echo ""
}

# Run All-Reduce test
echo "=========================================="
echo "Test 1: All-Reduce Operation"
echo "=========================================="
run_nccl_test "allreduce" "all_reduce_perf"

# Run All-Gather test
echo "=========================================="
echo "Test 2: All-Gather Operation"
echo "=========================================="
run_nccl_test "allgather" "all_gather_perf"

# Run Broadcast test
echo "=========================================="
echo "Test 3: Broadcast Operation"
echo "=========================================="
run_nccl_test "broadcast" "broadcast_perf"

# Run Reduce-Scatter test
echo "=========================================="
echo "Test 4: Reduce-Scatter Operation"
echo "=========================================="
run_nccl_test "reduce_scatter" "reduce_scatter_perf"

# Parse and summarize results
echo "=========================================="
echo "Results Summary"
echo "=========================================="

for result_file in "$RESULTS_DIR"/*.txt; do
    if [ -f "$result_file" ]; then
        echo "File: $(basename $result_file)"
        echo "Peak Performance:"
        grep -E "^\s+[0-9]+" "$result_file" | awk '{print $1, $4, $5}' | sort -k2 -nr | head -5
        echo ""
    fi
done

echo "All tests completed!"
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Expected Performance for 8x H100 GPUs:"
echo "  - All-Reduce: ~400 GB/s"
echo "  - All-Gather: ~350 GB/s"
echo ""
