#!/bin/bash
#
# NIXL UCX Backend Benchmark Test
#
# WARNING: This backend is known to have stability issues and poor performance
# Expected performance: ~0.85 GB/s (much worse than LIBFABRIC ~18 GB/s)
# Known issues: "target uri is not valid" ETCD errors
#
# For production use, prefer LIBFABRIC backend instead

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="/home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks"

echo "==================================================================="
echo "NIXL UCX Backend Benchmark Test"
echo "==================================================================="
echo ""
echo "WARNING: UCX backend is unstable and shows poor performance"
echo "Expected: ~0.85 GB/s (vs LIBFABRIC ~18 GB/s)"
echo "Known issues: ETCD 'target uri is not valid' errors"
echo ""
echo "This test is for comparison purposes only."
echo "==================================================================="
echo ""

# Check if workaround should be applied
if [ "$1" == "--with-workaround" ]; then
    echo "Applying DRAM workaround..."
    echo ""
    USE_DRAM=1
else
    echo "Running standard test (may fail with ETCD errors)"
    echo "Use --with-workaround flag to try DRAM-based workaround"
    echo ""
    USE_DRAM=0
fi

# Configuration
WORLD_SIZE=2
MASTER_ADDR="127.0.0.1"
MASTER_PORT=29500
STORE_PORT=29501

# UCX Environment Variables
export UCX_TLS=tcp,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=lo
export UCX_MEMTYPE_CACHE=n

if [ $USE_DRAM -eq 1 ]; then
    echo "WORKAROUND: Using DRAM instead of VRAM"
    export NIXL_USE_DRAM=1
    export NIXL_BUFFER_TYPE=cpu
fi

# ETCD configuration (often causes issues)
export NIXL_STORE_TYPE=etcd
export NIXL_ETCD_ENDPOINTS="http://${MASTER_ADDR}:${STORE_PORT}"

# Start ETCD server
echo "Starting ETCD server on port ${STORE_PORT}..."
pkill -f "etcd.*${STORE_PORT}" 2>/dev/null || true
sleep 1

etcd \
    --listen-client-urls "http://0.0.0.0:${STORE_PORT}" \
    --advertise-client-urls "http://${MASTER_ADDR}:${STORE_PORT}" \
    --listen-peer-urls "http://0.0.0.0:2380" \
    --initial-advertise-peer-urls "http://${MASTER_ADDR}:2380" \
    --initial-cluster "default=http://${MASTER_ADDR}:2380" \
    --data-dir "/tmp/etcd-nixl-ucx" \
    --log-level error \
    > /tmp/etcd-nixl-ucx.log 2>&1 &

ETCD_PID=$!
echo "ETCD PID: $ETCD_PID"
sleep 3

# Verify ETCD is running
if ! curl -s "http://${MASTER_ADDR}:${STORE_PORT}/health" > /dev/null; then
    echo "ERROR: ETCD failed to start"
    cat /tmp/etcd-nixl-ucx.log
    exit 1
fi

echo "ETCD server started successfully"
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    kill $ETCD_PID 2>/dev/null || true
    pkill -f "etcd.*${STORE_PORT}" 2>/dev/null || true
    rm -rf /tmp/etcd-nixl-ucx
    echo "Cleanup complete"
}
trap cleanup EXIT

# Test parameters
TENSOR_SIZE_MB=1024
NUM_ITERS=50
WARMUP_ITERS=5

echo "==================================================================="
echo "Test Configuration:"
echo "  Backend: UCX"
echo "  Transport: tcp,cuda_copy,cuda_ipc"
echo "  World Size: $WORLD_SIZE"
echo "  Tensor Size: ${TENSOR_SIZE_MB} MB"
echo "  Iterations: $NUM_ITERS (warmup: $WARMUP_ITERS)"
if [ $USE_DRAM -eq 1 ]; then
    echo "  Memory Type: DRAM (workaround enabled)"
else
    echo "  Memory Type: VRAM"
fi
echo "==================================================================="
echo ""

# Create test script
TEST_SCRIPT="/tmp/nixl_ucx_test_$$.py"
cat > "$TEST_SCRIPT" << 'PYTEST'
import os
import sys
import time
import torch
import torch.distributed as dist

def run_benchmark(rank, world_size, tensor_size_mb, num_iters, warmup_iters):
    """Run NIXL UCX backend benchmark"""

    # Initialize process group with UCX backend
    backend = "nccl"  # NIXL patches NCCL to use UCX

    # Get ETCD endpoints
    store_addr = os.environ.get("MASTER_ADDR", "127.0.0.1")
    store_port = int(os.environ.get("MASTER_PORT", "29500"))

    try:
        dist.init_process_group(
            backend=backend,
            init_method=f"tcp://{store_addr}:{store_port}",
            rank=rank,
            world_size=world_size,
            timeout=torch.distributed.timedelta(seconds=30)
        )
    except Exception as e:
        print(f"[Rank {rank}] ERROR: Failed to initialize process group: {e}")
        print(f"[Rank {rank}] This is the common 'target uri is not valid' ETCD error")
        sys.exit(1)

    print(f"[Rank {rank}] Process group initialized with UCX backend")

    # Determine device and memory type
    use_dram = os.environ.get("NIXL_USE_DRAM", "0") == "1"

    if use_dram:
        device = torch.device("cpu")
        print(f"[Rank {rank}] Using CPU/DRAM (workaround mode)")
    else:
        device = torch.device(f"cuda:{rank}")
        torch.cuda.set_device(device)
        print(f"[Rank {rank}] Using GPU/VRAM: {torch.cuda.get_device_name(device)}")

    # Create tensor
    tensor_size = (tensor_size_mb * 1024 * 1024) // 4  # Convert MB to float32 elements
    tensor = torch.randn(tensor_size, device=device)

    print(f"[Rank {rank}] Tensor size: {tensor_size_mb} MB")

    # Warmup
    if rank == 0:
        print(f"\n[Rank {rank}] Warming up ({warmup_iters} iterations)...")

    for i in range(warmup_iters):
        dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
        if not use_dram:
            torch.cuda.synchronize()

    # Benchmark
    if rank == 0:
        print(f"[Rank {rank}] Running benchmark ({num_iters} iterations)...")

    if not use_dram:
        torch.cuda.synchronize()
    dist.barrier()

    start_time = time.time()

    for i in range(num_iters):
        dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
        if not use_dram:
            torch.cuda.synchronize()

    if not use_dram:
        torch.cuda.synchronize()
    dist.barrier()

    end_time = time.time()

    # Calculate statistics
    elapsed_time = end_time - start_time
    avg_time_ms = (elapsed_time / num_iters) * 1000

    # Data transferred per iteration: (world_size - 1) * tensor_size for all-reduce
    data_per_iter_gb = (tensor_size_mb / 1024) * (world_size - 1)
    bandwidth_gbps = data_per_iter_gb / (avg_time_ms / 1000)

    if rank == 0:
        print(f"\n{'='*70}")
        print(f"NIXL UCX Backend Benchmark Results")
        print(f"{'='*70}")
        print(f"Backend: UCX")
        print(f"Transport: {os.environ.get('UCX_TLS', 'N/A')}")
        print(f"Memory Type: {'DRAM (workaround)' if use_dram else 'VRAM'}")
        print(f"World Size: {world_size}")
        print(f"Tensor Size: {tensor_size_mb} MB")
        print(f"Iterations: {num_iters}")
        print(f"Total Time: {elapsed_time:.3f} s")
        print(f"Avg Time/Iter: {avg_time_ms:.3f} ms")
        print(f"Bandwidth: {bandwidth_gbps:.2f} GB/s")
        print(f"{'='*70}")
        print(f"\nNOTE: Expected performance with UCX is ~0.85 GB/s")
        print(f"      This is significantly worse than LIBFABRIC (~18 GB/s)")
        print(f"      UCX backend is NOT recommended for production use")
        print(f"{'='*70}")

    dist.destroy_process_group()

    return bandwidth_gbps

if __name__ == "__main__":
    rank = int(sys.argv[1])
    world_size = int(sys.argv[2])
    tensor_size_mb = int(sys.argv[3])
    num_iters = int(sys.argv[4])
    warmup_iters = int(sys.argv[5])

    try:
        bandwidth = run_benchmark(rank, world_size, tensor_size_mb, num_iters, warmup_iters)
        if rank == 0:
            if bandwidth < 1.0:
                print(f"\nWARNING: Performance is critically low ({bandwidth:.2f} GB/s)")
            sys.exit(0)
    except Exception as e:
        print(f"[Rank {rank}] FATAL ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
PYTEST

echo "Starting benchmark processes..."
echo ""

# Launch processes
for rank in $(seq 0 $((WORLD_SIZE - 1))); do
    CUDA_VISIBLE_DEVICES=$rank \
    MASTER_ADDR=$MASTER_ADDR \
    MASTER_PORT=$MASTER_PORT \
    python3 "$TEST_SCRIPT" $rank $WORLD_SIZE $TENSOR_SIZE_MB $NUM_ITERS $WARMUP_ITERS \
        > "/tmp/nixl_ucx_rank_${rank}.log" 2>&1 &

    PIDS[$rank]=$!
    echo "Launched rank $rank (PID: ${PIDS[$rank]})"
done

echo ""
echo "Waiting for all processes to complete..."
echo ""

# Wait for all processes and check results
FAILED=0
for rank in $(seq 0 $((WORLD_SIZE - 1))); do
    if wait ${PIDS[$rank]}; then
        echo "Rank $rank completed successfully"
    else
        echo "Rank $rank FAILED"
        FAILED=1
    fi
done

echo ""
echo "==================================================================="

# Display logs
for rank in $(seq 0 $((WORLD_SIZE - 1))); do
    echo ""
    echo "--- Rank $rank Output ---"
    cat "/tmp/nixl_ucx_rank_${rank}.log"
done

echo ""
echo "==================================================================="

# Cleanup test files
rm -f "$TEST_SCRIPT"
rm -f /tmp/nixl_ucx_rank_*.log

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "BENCHMARK FAILED"
    echo ""
    echo "Common UCX backend issues:"
    echo "  1. 'target uri is not valid' ETCD error"
    echo "  2. UCX library initialization failures"
    echo "  3. CUDA IPC setup failures"
    echo ""
    echo "Try running with workaround: $0 --with-workaround"
    echo "Or use LIBFABRIC backend instead (much better performance)"
    echo ""
    exit 1
else
    echo ""
    echo "BENCHMARK COMPLETED"
    echo ""
    echo "Performance note:"
    echo "  UCX backend typically achieves ~0.85 GB/s"
    echo "  LIBFABRIC backend achieves ~18 GB/s (21x faster!)"
    echo ""
    echo "Recommendation: Use LIBFABRIC backend for production workloads"
    echo ""
fi
