#!/bin/bash

# NCCL All-Reduce Specific Test Script
# Focused testing for all-reduce operations with detailed profiling

set -e

# Configuration
NUM_GPUS=${NUM_GPUS:-8}
MIN_SIZE=${MIN_SIZE:-$((1024*1024))}        # 1 MB
MAX_SIZE=${MAX_SIZE:-$((8*1024*1024*1024))} # 8 GB
WARMUP_ITERS=${WARMUP_ITERS:-10}
ITERS=${ITERS:-50}
DATA_TYPE=${DATA_TYPE:-float}

# NCCL Environment Variables
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export NCCL_DEBUG_SUBSYS=${NCCL_DEBUG_SUBSYS:-INIT,COLL,ENV}
export NCCL_IB_DISABLE=0
export NCCL_SOCKET_IFNAME=ens

# EFA-specific optimizations for multi-node
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1
export NCCL_TREE_THRESHOLD=4294967296
export NCCL_PROTO=Simple

# Performance tuning
export NCCL_BUFFSIZE=2097152
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0
export NCCL_NET_GDR_LEVEL=5
export NCCL_CROSS_NIC=1

# Check for nccl-tests
if ! command -v all_reduce_perf &> /dev/null; then
    echo "Error: all_reduce_perf not found."
    echo ""
    echo "To install NCCL tests:"
    echo "  git clone https://github.com/NVIDIA/nccl-tests.git"
    echo "  cd nccl-tests"
    echo "  make MPI=1 MPI_HOME=/opt/amazon/openmpi"
    echo ""
    exit 1
fi

# Create results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="allreduce_results_${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

echo "=========================================="
echo "NCCL All-Reduce Benchmark"
echo "=========================================="
echo "Configuration:"
echo "  GPUs: $NUM_GPUS"
echo "  Message Size: $MIN_SIZE - $MAX_SIZE bytes"
echo "  Warmup Iterations: $WARMUP_ITERS"
echo "  Test Iterations: $ITERS"
echo "  Data Type: $DATA_TYPE"
echo "  Results Directory: $RESULTS_DIR"
echo "=========================================="
echo ""

# Print NCCL environment configuration
echo "NCCL Configuration:"
echo "  NCCL_DEBUG: $NCCL_DEBUG"
echo "  NCCL_TREE_THRESHOLD: $NCCL_TREE_THRESHOLD"
echo "  FI_PROVIDER: $FI_PROVIDER"
echo "  FI_EFA_USE_DEVICE_RDMA: $FI_EFA_USE_DEVICE_RDMA"
echo "=========================================="
echo ""

# Run all-reduce test with detailed output
OUTPUT_FILE="$RESULTS_DIR/allreduce_${NUM_GPUS}gpus_${TIMESTAMP}.txt"
LOG_FILE="$RESULTS_DIR/allreduce_debug_${NUM_GPUS}gpus_${TIMESTAMP}.log"

echo "Starting All-Reduce test..."
echo "Output: $OUTPUT_FILE"
echo "Debug Log: $LOG_FILE"
echo ""

# Run the test
all_reduce_perf \
    -b $MIN_SIZE \
    -e $MAX_SIZE \
    -f 2 \
    -g $NUM_GPUS \
    -w $WARMUP_ITERS \
    -n $ITERS \
    -c 1 \
    -t 1 \
    2>&1 | tee "$OUTPUT_FILE"

# Copy debug logs if they exist
if [ -f "nccl_debug.log" ]; then
    cp nccl_debug.log "$LOG_FILE"
fi

echo ""
echo "=========================================="
echo "Results Analysis"
echo "=========================================="

# Extract peak bandwidth
PEAK_BW=$(grep -E "^\s+[0-9]+" "$OUTPUT_FILE" | awk '{print $4}' | sort -nr | head -1)
echo "Peak Bandwidth: ${PEAK_BW} GB/s"

# Extract bandwidth for specific message sizes
echo ""
echo "Bandwidth by Message Size:"
echo "Size         Out-of-Place   In-Place    Avg Time"
grep -E "^\s+[0-9]+" "$OUTPUT_FILE" | awk '{printf "%12s  %8s GB/s  %8s GB/s  %8s us\n", $1, $4, $5, $6}' | head -20

echo ""
echo "=========================================="
echo "Performance Analysis"
echo "=========================================="

# Calculate expected vs actual performance
EXPECTED_BW=400
if [ ! -z "$PEAK_BW" ]; then
    EFFICIENCY=$(echo "scale=2; $PEAK_BW / $EXPECTED_BW * 100" | bc)
    echo "Expected Bandwidth (8x H100): ${EXPECTED_BW} GB/s"
    echo "Measured Bandwidth: ${PEAK_BW} GB/s"
    echo "Efficiency: ${EFFICIENCY}%"

    if (( $(echo "$PEAK_BW < 350" | bc -l) )); then
        echo ""
        echo "WARNING: Performance below expected threshold (350 GB/s)"
        echo "Troubleshooting steps:"
        echo "  1. Check EFA connectivity: fi_info -p efa"
        echo "  2. Verify GPU topology: nvidia-smi topo -m"
        echo "  3. Check NCCL debug logs in: $LOG_FILE"
        echo "  4. Ensure EFA is enabled and properly configured"
    fi
fi

echo ""
echo "Test completed successfully!"
echo "Results saved to: $RESULTS_DIR"
echo ""
