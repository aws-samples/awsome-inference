#!/bin/bash
# Fix for nixlbench ETCD URI validation error

echo "═══════════════════════════════════════════════════════════"
echo "          NIXLBENCH ETCD URI ERROR FIX"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 1: Use DRAM instead of VRAM (avoids GPU URI issue)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The VRAM URI format might be causing the issue. Try DRAM:"
echo ""
echo "# On BOTH pods simultaneously:"
cat << 'EOF'
BENCHMARK_GROUP="dram-test-$(date +%s)"

nixlbench \
  --etcd_endpoints http://10.1.238.41:2379 \
  --benchmark_group ${BENCHMARK_GROUP} \
  --backend UCX \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --start_block_size 134217728 \
  --warmup_iter 5
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 2: Use correct parameter names (based on help output)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# The help showed these exact parameter names:"
cat << 'EOF'
BENCHMARK_GROUP="fix2-$(date +%s)"

nixlbench \
  --etcd_endpoints http://10.1.238.41:2379 \
  --benchmark_group ${BENCHMARK_GROUP} \
  --backend UCX \
  --worker_type nixl \
  --target_seg_type DRAM \
  --scheme pairwise \
  --op_type WRITE \
  --total_buffer_size 1073741824 \
  --start_block_size 4096 \
  --start_batch_size 1 \
  --warmup_iter 100 \
  --device_list all
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 3: Try with explicit device instead of 'all'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
BENCHMARK_GROUP="device-test-$(date +%s)"

nixlbench \
  --etcd_endpoints http://10.1.238.41:2379 \
  --benchmark_group ${BENCHMARK_GROUP} \
  --backend UCX \
  --device_list rdmap113s0:1 \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --start_block_size 134217728 \
  --warmup_iter 5
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 4: Debug ETCD content to see what's being stored"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# First, watch ETCD in another terminal to see what's happening:
# Terminal 1 (monitoring):
curl http://10.1.238.41:2379/v3/kv/range \
  -X POST \
  -d '{"key": "AA==", "range_end": "AA==", "keys_only": false}'

# Or if etcdctl is available:
ETCDCTL_API=3 etcdctl --endpoints=http://10.1.238.41:2379 watch "" --prefix

# Terminal 2 & 3: Run nixlbench and watch what gets stored
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 5: Set environment variables to override"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Set these environment variables before running nixlbench:
export NIXL_DISABLE_URI_VALIDATION=1
export NIXL_ETCD_PREFIX=/nixl
export NIXL_AGENT_URI_FORMAT=simple
export UCX_NET_DEVICES=all
export UCX_TLS=srd,cuda_copy,cuda_ipc

BENCHMARK_GROUP="env-test-$(date +%s)"

nixlbench \
  --etcd_endpoints http://10.1.238.41:2379 \
  --benchmark_group ${BENCHMARK_GROUP} \
  --backend UCX \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 6: Use different backend (POSIX or GDS)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Try POSIX backend (simpler, no GPU URIs):
BENCHMARK_GROUP="posix-test-$(date +%s)"

nixlbench \
  --etcd_endpoints http://10.1.238.41:2379 \
  --benchmark_group ${BENCHMARK_GROUP} \
  --backend POSIX \
  --target_seg_type DRAM \
  --filepath /tmp/nixl_test_file \
  --total_buffer_size 1073741824
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ANALYSIS: Why this error occurs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The error 'Failed to store agent target prefix key in etcd: the target uri is not valid'"
echo "happens when nixlbench tries to store GPU/memory segment metadata in ETCD."
echo ""
echo "The URI format for VRAM segments might include:"
echo "- GPU device ID"
echo "- Memory addresses"
echo "- RDMA handles"
echo ""
echo "Something in this URI format is being rejected by ETCD or nixlbench's validation."
echo ""
echo "Try FIX 1 first (use DRAM instead of VRAM) - this often works!"
echo ""