#!/bin/bash

# NCCL Bandwidth Testing Script
# Tests bandwidth across GPUs with various message sizes
# Includes both intra-node and inter-node testing

set -e

# Test Configuration
NUM_GPUS=${NUM_GPUS:-8}
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
    echo "Error: NCCL tests not found."
    echo "Please install from: https://github.com/NVIDIA/nccl-tests"
    exit 1
fi

# Create results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="bandwidth_results_${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

echo "=========================================="
echo "NCCL Bandwidth Benchmark"
echo "=========================================="
echo "GPUs: $NUM_GPUS"
echo "Warmup Iterations: $WARMUP_ITERS"
echo "Test Iterations: $ITERS"
echo "Results Directory: $RESULTS_DIR"
echo "=========================================="
echo ""

# Function to run bandwidth test for a specific size range
run_bandwidth_test() {
    local test_name=$1
    local min_size=$2
    local max_size=$3
    local step_factor=$4
    local output_file="$RESULTS_DIR/${test_name}_${TIMESTAMP}.txt"

    echo "Running $test_name..."
    echo "  Size range: $min_size - $max_size bytes"
    echo "  Output: $output_file"

    all_reduce_perf \
        -b $min_size \
        -e $max_size \
        -f $step_factor \
        -g $NUM_GPUS \
        -w $WARMUP_ITERS \
        -n $ITERS \
        -c 1 \
        2>&1 | tee "$output_file"

    echo ""
}

# Test 1: Small messages (1KB to 1MB)
echo "=========================================="
echo "Test 1: Small Messages (1KB - 1MB)"
echo "=========================================="
run_bandwidth_test "small_messages" $((1024)) $((1024*1024)) 2

# Test 2: Medium messages (1MB to 128MB)
echo "=========================================="
echo "Test 2: Medium Messages (1MB - 128MB)"
echo "=========================================="
run_bandwidth_test "medium_messages" $((1024*1024)) $((128*1024*1024)) 2

# Test 3: Large messages (128MB to 2GB)
echo "=========================================="
echo "Test 3: Large Messages (128MB - 2GB)"
echo "=========================================="
run_bandwidth_test "large_messages" $((128*1024*1024)) $((2*1024*1024*1024)) 2

# Test 4: Very large messages (2GB to 8GB)
echo "=========================================="
echo "Test 4: Very Large Messages (2GB - 8GB)"
echo "=========================================="
run_bandwidth_test "xlarge_messages" $((2*1024*1024*1024)) $((8*1024*1024*1024)) 2

# Test all collective operations with optimal message size
echo "=========================================="
echo "Test 5: All Collectives (128MB - 1GB)"
echo "=========================================="
OPTIMAL_MIN=$((128*1024*1024))
OPTIMAL_MAX=$((1024*1024*1024))

# All-Reduce
echo "Testing All-Reduce..."
all_reduce_perf -b $OPTIMAL_MIN -e $OPTIMAL_MAX -f 2 -g $NUM_GPUS -w $WARMUP_ITERS -n $ITERS \
    2>&1 | tee "$RESULTS_DIR/allreduce_optimal_${TIMESTAMP}.txt"

# All-Gather
echo "Testing All-Gather..."
all_gather_perf -b $OPTIMAL_MIN -e $OPTIMAL_MAX -f 2 -g $NUM_GPUS -w $WARMUP_ITERS -n $ITERS \
    2>&1 | tee "$RESULTS_DIR/allgather_optimal_${TIMESTAMP}.txt"

# Reduce-Scatter
echo "Testing Reduce-Scatter..."
reduce_scatter_perf -b $OPTIMAL_MIN -e $OPTIMAL_MAX -f 2 -g $NUM_GPUS -w $WARMUP_ITERS -n $ITERS \
    2>&1 | tee "$RESULTS_DIR/reducescatter_optimal_${TIMESTAMP}.txt"

# All-to-All
echo "Testing All-to-All..."
alltoall_perf -b $OPTIMAL_MIN -e $OPTIMAL_MAX -f 2 -g $NUM_GPUS -w $WARMUP_ITERS -n $ITERS \
    2>&1 | tee "$RESULTS_DIR/alltoall_optimal_${TIMESTAMP}.txt"

echo ""
echo "=========================================="
echo "Bandwidth Analysis"
echo "=========================================="

# Analyze results
for result_file in "$RESULTS_DIR"/*.txt; do
    if [ -f "$result_file" ]; then
        TEST_NAME=$(basename "$result_file" .txt)
        echo ""
        echo "Test: $TEST_NAME"
        echo "----------------------------------------"

        # Get peak bandwidth
        PEAK=$(grep -E "^\s+[0-9]+" "$result_file" | awk '{print $4}' | sort -nr | head -1)
        echo "Peak Bandwidth: ${PEAK} GB/s"

        # Get average bandwidth for large messages
        AVG=$(grep -E "^\s+[0-9]+" "$result_file" | tail -10 | awk '{sum+=$4; count++} END {if(count>0) print sum/count; else print "N/A"}')
        echo "Average (large messages): ${AVG} GB/s"

        # Get bandwidth for 1GB messages specifically
        BW_1GB=$(grep -E "^\s+1073741824\s+" "$result_file" | awk '{print $4}' || echo "N/A")
        if [ "$BW_1GB" != "N/A" ]; then
            echo "Bandwidth at 1GB: ${BW_1GB} GB/s"
        fi
    fi
done

echo ""
echo "=========================================="
echo "Performance Summary"
echo "=========================================="

# Create summary CSV
SUMMARY_FILE="$RESULTS_DIR/bandwidth_summary.csv"
echo "Test,Message Size,Bandwidth (GB/s),Latency (us),Iterations" > "$SUMMARY_FILE"

for result_file in "$RESULTS_DIR"/*.txt; do
    if [ -f "$result_file" ]; then
        TEST_NAME=$(basename "$result_file" .txt)
        grep -E "^\s+[0-9]+" "$result_file" | awk -v test="$TEST_NAME" '{print test","$1","$4","$6","$8}' >> "$SUMMARY_FILE"
    fi
done

echo "Summary saved to: $SUMMARY_FILE"
echo ""

# Performance expectations
echo "Expected Performance (8x H100 GPUs):"
echo "  - All-Reduce: ~400 GB/s"
echo "  - All-Gather: ~350 GB/s"
echo "  - Reduce-Scatter: ~350 GB/s"
echo "  - All-to-All: ~300 GB/s"
echo ""

# Check if we meet expectations
ALLREDUCE_PEAK=$(grep -E "^\s+[0-9]+" "$RESULTS_DIR/allreduce_optimal_${TIMESTAMP}.txt" 2>/dev/null | awk '{print $4}' | sort -nr | head -1 || echo "0")

if [ ! -z "$ALLREDUCE_PEAK" ] && (( $(echo "$ALLREDUCE_PEAK > 0" | bc -l) )); then
    if (( $(echo "$ALLREDUCE_PEAK >= 350" | bc -l) )); then
        echo "✓ Performance meets expectations!"
    else
        echo "⚠ Performance below expected threshold"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check GPU topology: nvidia-smi topo -m"
        echo "  2. Verify EFA: fi_info -p efa"
        echo "  3. Check NCCL logs in: $RESULTS_DIR"
        echo "  4. Ensure GPUs are not throttled: nvidia-smi -q | grep -A 5 Clocks"
    fi
fi

echo ""
echo "All bandwidth tests completed!"
echo "Results saved to: $RESULTS_DIR"
echo ""
