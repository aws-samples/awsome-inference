#!/bin/bash
# Workaround approaches for nixlbench ETCD issues

echo "═══════════════════════════════════════════════════════════"
echo "    NIXLBENCH WORKAROUNDS FOR ETCD URI ERRORS"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "APPROACH 1: Try without ETCD (environment variables)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# On Pod 1 (IP: 10.1.238.41):"
cat << 'EOF'
export NIXL_RANK=0
export NIXL_WORLD_SIZE=2
export MASTER_ADDR=10.1.238.41
export MASTER_PORT=29500
export NIXL_MASTER_ADDR=10.1.238.41
export NIXL_MASTER_PORT=29500

nixlbench \
  --backend UCX \
  --target_seg_type VRAM \
  --total_buffer_size 1073741824 \
  --start_block_size 134217728 \
  --warmup_iter 5 \
  --scheme pairwise
EOF
echo ""
echo "# On Pod 2 (simultaneously):"
cat << 'EOF'
export NIXL_RANK=1
export NIXL_WORLD_SIZE=2
export MASTER_ADDR=10.1.238.41
export MASTER_PORT=29500
export NIXL_MASTER_ADDR=10.1.238.41
export NIXL_MASTER_PORT=29500

nixlbench \
  --backend UCX \
  --target_seg_type VRAM \
  --total_buffer_size 1073741824 \
  --start_block_size 134217728 \
  --warmup_iter 5 \
  --scheme pairwise
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "APPROACH 2: Use CPU memory instead of VRAM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Sometimes the VRAM URI causes issues. Try DRAM:"
cat << 'EOF'
nixlbench \
  --etcd_endpoints http://10.1.238.41:2379 \
  --benchmark_group test2 \
  --backend UCX \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --start_block_size 134217728 \
  --warmup_iter 5
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "APPROACH 3: Try other NIXL test binaries"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# nixl_test might work differently:"
cat << 'EOF'
# Check what other test binaries exist:
ls /workspace/nixl/nixl_*

# Try nixl_test:
nixl_test

# Or nixl_example:
nixl_example
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "APPROACH 4: Use UCX directly (skip nixlbench)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Since UCX worked at 307 MB/s with SRD transport:"
echo ""
echo "# On Pod 1 (server):"
cat << 'EOF'
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 20 -w 10 -p 12345
EOF
echo ""
echo "# On Pod 2 (client) - after server starts:"
cat << 'EOF'
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 8589934592 -n 20 -w 10 -p 12345
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "APPROACH 5: Check ETCD content to debug"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Install etcdctl if not available:
apt-get update && apt-get install -y etcd-client

# Check what's in ETCD:
export ETCDCTL_API=3
etcdctl --endpoints=http://10.1.238.41:2379 get "" --prefix

# Clear ETCD state:
etcdctl --endpoints=http://10.1.238.41:2379 del "" --prefix

# Try nixlbench again with clean state
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DIAGNOSIS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The error 'Failed to store agent target prefix key in etcd: the target uri is not valid'"
echo "indicates nixlbench is trying to store GPU/memory segment information in ETCD"
echo "but the URI format it's generating is being rejected."
echo ""
echo "This is a known issue from the November 2024 tests."
echo "The infrastructure is fine (UCX achieved 284.98 GB/s)."
echo "This is a nixlbench software bug."
echo ""
echo "RECOMMENDATION: Use UCX perftest directly (Approach 4) for bandwidth testing."
echo "It's proven to work and gives accurate results."
echo ""