#!/bin/bash
# NIXLBENCH Commands for Testing Between Two Pods

echo "═══════════════════════════════════════════════════════════"
echo "              NIXLBENCH TEST COMMANDS"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Check nixlbench help/usage"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# See available options:
nixlbench --help

# Or try:
nixlbench -h
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Common nixlbench patterns"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Option A: MPI-style launch (if it uses MPI):"
cat << 'EOF'
# On Pod 1:
export NIXL_RANK=0
export NIXL_WORLD_SIZE=2
export MASTER_ADDR=10.1.238.41
export MASTER_PORT=5555
nixlbench

# On Pod 2:
export NIXL_RANK=1
export NIXL_WORLD_SIZE=2
export MASTER_ADDR=10.1.238.41
export MASTER_PORT=5555
nixlbench
EOF
echo ""

echo "# Option B: Client-Server mode (common patterns):"
cat << 'EOF'
# On Pod 1 (Server):
nixlbench -s  # or --server
nixlbench --listen 5555
nixlbench --mode server
nixlbench server

# On Pod 2 (Client):
nixlbench -c 10.1.238.41  # or --client
nixlbench --connect 10.1.238.41:5555
nixlbench --mode client --host 10.1.238.41
nixlbench client 10.1.238.41
EOF
echo ""

echo "# Option C: Direct specification:"
cat << 'EOF'
# On Pod 1:
nixlbench --local-ip 10.1.238.41 --remote-ip 10.1.199.72

# On Pod 2:
nixlbench --local-ip 10.1.199.72 --remote-ip 10.1.238.41
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Try other NIXL test binaries"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# nixl_test might be the actual benchmark:
nixl_test --help

# Or nixl_example:
nixl_example --help

# Try running without arguments to see usage:
nixl_test
nixl_example
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Check for configuration files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Look for example configs or scripts:
ls /workspace/nixl/*.sh
ls /workspace/nixl/*.conf
ls /workspace/nixl/*.yaml
cat /workspace/nixl/README* 2>/dev/null

# Check environment variables:
env | grep -i nixl
env | grep -i efa
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Fallback - Use UCX with NIXL environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Since UCX worked, we can test with NIXL environment set:
export NIXL_ENABLE=1
export NIXL_NET_DEVICES=all
export NIXL_NUM_RAILS=32

# Then run UCX test:
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 20 -p 10020
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "First, run: nixlbench --help"
echo "This will show us the correct syntax!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""