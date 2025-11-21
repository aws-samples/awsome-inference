#!/bin/bash
# Iterative UCX test script for AWS EFA - building from working baseline
# Incrementally adds optimizations to maximize bandwidth across 32 EFA devices

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    AWS EFA UCX Iterative Performance Test${NC}"
echo -e "${BLUE}    Building from Working Baseline (284.57 GB/s)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Get pod names - assuming you have them from previous test
SERVER_POD="nixl-benchmark-84d8b89c5b-7csx9"
CLIENT_POD="nixl-benchmark-84d8b89c5b-rdlmh"
SERVER_IP="192.168.78.169"

echo -e "${GREEN}Using pods from previous successful test:${NC}"
echo "  Server: $SERVER_POD (IP: $SERVER_IP)"
echo "  Client: $CLIENT_POD"
echo ""

# Function to run a test iteration
run_test() {
    local test_name="$1"
    local test_desc="$2"
    local server_env="$3"
    local client_env="$4"
    local size="${5:-2147483648}"  # Default 2GB
    local iterations="${6:-10}"
    local warmup="${7:-5}"
    local port="$8"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test: ${test_name}${NC}"
    echo -e "${CYAN}${test_desc}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Kill any existing server
    kubectl exec $SERVER_POD -- pkill ucx_perftest 2>/dev/null || true
    sleep 2

    # Start server
    echo "Starting server with configuration..."
    kubectl exec $SERVER_POD -- bash -c "
${server_env}
nohup ucx_perftest -t ucp_put_bw -m cuda -s ${size} -n ${iterations} -w ${warmup} -p ${port} > /tmp/server_${test_name}.log 2>&1 &
sleep 3
"

    # Run client
    echo "Running client test..."
    echo -e "${YELLOW}Configuration:${NC}"
    echo "$client_env" | sed 's/^/  /'
    echo ""

    kubectl exec $CLIENT_POD -- bash -c "
${client_env}
ucx_perftest -t ucp_put_bw -m cuda -s ${size} -n ${iterations} -w ${warmup} -p ${port} ${SERVER_IP} 2>&1 | tee /tmp/client_${test_name}.log
" | grep -E "Final:|bandwidth:|Bandwidth:" | tail -3

    # Kill server
    kubectl exec $SERVER_POD -- pkill ucx_perftest 2>/dev/null || true
    sleep 1
}

# Test 1: Baseline (your working configuration)
run_test "baseline" \
    "Reproducing your working configuration" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all" \
    2147483648 10 5 10001

# Test 2: Add multi-path support
run_test "multipath" \
    "Adding UCX_IB_NUM_PATHS=32 for multi-path" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32" \
    2147483648 10 5 10002

# Test 3: Add RDMA optimization
run_test "rdma_opt" \
    "Adding RDMA optimizations and GDR copy" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y" \
    2147483648 10 5 10003

# Test 4: Add rail configuration
run_test "rails" \
    "Adding UCX_MAX_RNDV_RAILS for multi-rail support" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y" \
    2147483648 10 5 10004

# Test 5: Optimize thresholds
run_test "thresholds" \
    "Optimizing RNDV and ZCOPY thresholds" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_IB_MLX5_DEVX=y" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_IB_MLX5_DEVX=y" \
    2147483648 10 5 10005

# Test 6: Disable flow control
run_test "no_fc" \
    "Disabling flow control for maximum throughput" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_MLX5_DEVX=y" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_MLX5_DEVX=y" \
    2147483648 10 5 10006

# Test 7: Large buffer test (8GB)
run_test "large_buffer" \
    "Testing with larger buffer size (8GB)" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_MLX5_DEVX=y" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_MLX5_DEVX=y" \
    8589934592 20 10 10007

# Test 8: Add memory registration optimization
run_test "mem_opt" \
    "Adding memory registration cache optimizations" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_REG_METHODS=rcache,odp
export UCX_IB_RCACHE_MEM_PRIO=1000
export UCX_IB_MLX5_DEVX=y" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_REG_METHODS=rcache,odp
export UCX_IB_RCACHE_MEM_PRIO=1000
export UCX_IB_MLX5_DEVX=y" \
    8589934592 20 10 10008

# Test 9: EFA-specific optimizations
run_test "efa_specific" \
    "Adding EFA-specific environment variables" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_IB_REG_METHODS=rcache,odp
export UCX_IB_MLX5_DEVX=y
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1" \
    "export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_RC_FC_ENABLE=n
export UCX_IB_REG_METHODS=rcache,odp
export UCX_IB_MLX5_DEVX=y
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1" \
    8589934592 20 10 10009

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Iterative UCX Tests Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Summary of configurations tested:"
echo "1. Baseline - Your working configuration"
echo "2. Multi-path - Added UCX_IB_NUM_PATHS=32"
echo "3. RDMA optimizations - Added GDR copy and DEVX"
echo "4. Rails - Added UCX_MAX_RNDV_RAILS=32"
echo "5. Thresholds - Optimized RNDV and ZCOPY"
echo "6. No flow control - Disabled FC for max throughput"
echo "7. Large buffer - Tested with 8GB transfers"
echo "8. Memory optimization - Added rcache and ODP"
echo "9. EFA-specific - Added FI_EFA variables"
echo ""
echo "To check which configuration gave best performance:"
echo "  grep -h 'Final:' /tmp/client_*.log on client pod"
echo ""
echo "Next steps:"
echo "1. Identify the best performing configuration"
echo "2. Run longer tests with that configuration"
echo "3. Test with multiple concurrent streams if needed"
echo ""