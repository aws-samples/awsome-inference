#!/bin/bash
# NIXLBENCH Commands with Correct Syntax

echo "═══════════════════════════════════════════════════════════"
echo "          NIXLBENCH - CORRECT USAGE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "nixlbench uses ETCD for coordination between nodes"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION 1: Basic Pairwise Test (Default)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# On BOTH pods simultaneously (they coordinate via ETCD):"
cat << 'EOF'
# Set ETCD endpoint (use one pod's IP as ETCD server, or external ETCD)
export ETCD_ENDPOINTS="10.1.238.41:2379"

# Run on Pod 1:
nixlbench \
  -etcd_endpoints="10.1.238.41:2379" \
  -backend=UCX \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=8589934592 \
  -start_block_size=1073741824 \
  -warmup_iter=10 \
  -benchmark_group=test1

# Run on Pod 2 (same command):
nixlbench \
  -etcd_endpoints="10.1.238.41:2379" \
  -backend=UCX \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=8589934592 \
  -start_block_size=1073741824 \
  -warmup_iter=10 \
  -benchmark_group=test1
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION 2: Without ETCD (if ETCD not available)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Try running without ETCD (may work with environment variables):"
cat << 'EOF'
# On Pod 1:
export NIXL_RANK=0
export NIXL_WORLD_SIZE=2
export MASTER_ADDR=10.1.238.41
export MASTER_PORT=5555

nixlbench \
  -backend=UCX \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=8589934592 \
  -start_block_size=1073741824

# On Pod 2:
export NIXL_RANK=1
export NIXL_WORLD_SIZE=2
export MASTER_ADDR=10.1.238.41
export MASTER_PORT=5555

nixlbench \
  -backend=UCX \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=8589934592 \
  -start_block_size=1073741824
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION 3: Test with Multiple Threads for Higher Performance"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Run on both pods:
nixlbench \
  -etcd_endpoints="10.1.238.41:2379" \
  -backend=UCX \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=17179869184 \
  -start_block_size=2147483648 \
  -num_threads=8 \
  -enable_pt=true \
  -warmup_iter=10 \
  -benchmark_group=perf_test
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION 4: Quick Test with Smaller Buffer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# For quick testing (1GB buffer):
nixlbench \
  -backend=UCX \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=1073741824 \
  -start_block_size=134217728 \
  -warmup_iter=5
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION 5: GDS Backend (GPU Direct Storage)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
nixlbench \
  -backend=GDS_MT \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=8589934592 \
  -gds_mt_num_threads=32 \
  -gds_batch_limit=256
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "KEY PARAMETERS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "-backend: UCX (default), UCX_MO, GDS, GDS_MT"
echo "-device_list: all (to use all 32 NICs)"
echo "-scheme: pairwise, maytoone, onetomany, tp"
echo "-target_seg_type: VRAM (GPU memory) or DRAM"
echo "-total_buffer_size: Total data size (default 8GB)"
echo "-start_block_size: Transfer block size"
echo "-num_threads: Number of threads for parallel transfers"
echo "-enable_pt: Enable progress thread for better performance"
echo ""
echo "IMPORTANT:"
echo "1. Both pods must run the same command simultaneously"
echo "2. Use the same -benchmark_group value on both pods"
echo "3. If ETCD is not available, the benchmark may fail"
echo "4. Monitor your network dashboard to see NIC utilization"
echo ""