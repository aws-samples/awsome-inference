#!/bin/bash
# UCX Multi-NIC Performance Test Script
# Utilizes all available EFA devices for maximum bandwidth

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    UCX Multi-NIC Performance Test (32 NICs)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Get pod names
SERVER_POD=$(kubectl get pods -l app=nixl-benchmark --no-headers | awk 'NR==1 {print $1}')
CLIENT_POD=$(kubectl get pods -l app=nixl-benchmark --no-headers | awk 'NR==2 {print $1}')

if [ -z "$SERVER_POD" ] || [ -z "$CLIENT_POD" ]; then
    echo -e "${RED}Error: Need at least 2 nixl-benchmark pods running${NC}"
    echo "Current pods:"
    kubectl get pods -l app=nixl-benchmark
    exit 1
fi

echo -e "${GREEN}✓ Found pods:${NC}"
echo "  Server: $SERVER_POD"
echo "  Client: $CLIENT_POD"
echo ""

# Get server IP
SERVER_IP=$(kubectl get pod $SERVER_POD -o jsonpath='{.status.podIP}')
echo -e "${GREEN}✓ Server IP: $SERVER_IP${NC}"
echo ""

# Check available EFA devices
echo -e "${YELLOW}Checking EFA devices on server pod...${NC}"
kubectl exec $SERVER_POD -- bash -c 'ls /dev/infiniband/ 2>/dev/null | wc -l || echo "0"' | while read count; do
    echo "  Available EFA devices: $count"
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 1: Single NIC Baseline${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Kill any existing ucx_perftest processes
kubectl exec $SERVER_POD -- pkill ucx_perftest 2>/dev/null || true
kubectl exec $CLIENT_POD -- pkill ucx_perftest 2>/dev/null || true
sleep 2

# Start server with single NIC
echo "Starting UCX server (single NIC)..."
kubectl exec $SERVER_POD -- bash -c '
export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=mlx5_0:1
ucx_perftest -t ucp_put_bw -m cuda -s 1073741824 -n 10 -w 10 -p 12345 > /tmp/server_single.log 2>&1 &
sleep 3
'

# Run client test
echo "Running client test (single NIC)..."
kubectl exec $CLIENT_POD -- bash -c "
export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=mlx5_0:1
ucx_perftest -t ucp_put_bw -m cuda -s 1073741824 -n 10 -w 10 -p 12345 $SERVER_IP 2>&1 | tee /tmp/client_single.log
" | tail -5

# Kill server
kubectl exec $SERVER_POD -- pkill ucx_perftest 2>/dev/null || true
sleep 2

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 2: Multi-NIC with UCX_IB_NUM_PATHS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Start server with multi-path
echo "Starting UCX server (multi-path, 32 NICs)..."
kubectl exec $SERVER_POD -- bash -c '
export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_IB_GID_INDEX=auto
ucx_perftest -t ucp_put_bw -m cuda -s 2147483648 -n 20 -w 20 -p 12346 > /tmp/server_multipath.log 2>&1 &
sleep 3
'

# Run client test with multi-path
echo "Running client test (multi-path, 32 NICs)..."
kubectl exec $CLIENT_POD -- bash -c "
export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_IB_GID_INDEX=auto
ucx_perftest -t ucp_put_bw -m cuda -s 2147483648 -n 20 -w 20 -p 12346 $SERVER_IP 2>&1 | tee /tmp/client_multipath.log
" | tail -5

# Kill server
kubectl exec $SERVER_POD -- pkill ucx_perftest 2>/dev/null || true
sleep 2

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 3: Multi-NIC with Rail Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Start server with rail config
echo "Starting UCX server (rail config, all devices)..."
kubectl exec $SERVER_POD -- bash -c '
export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y
ucx_perftest -t ucp_put_bw -m cuda -s 4294967296 -n 50 -w 32 -p 12347 > /tmp/server_rail.log 2>&1 &
sleep 3
'

# Run client test with rail config
echo "Running client test (rail config, all devices)..."
kubectl exec $CLIENT_POD -- bash -c "
export UCX_TLS=ib,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y
ucx_perftest -t ucp_put_bw -m cuda -s 4294967296 -n 50 -w 32 -p 12347 $SERVER_IP 2>&1 | tee /tmp/client_rail.log
" | tail -5

# Kill server
kubectl exec $SERVER_POD -- pkill ucx_perftest 2>/dev/null || true
sleep 2

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 4: Maximum Performance Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Start server with maximum performance settings
echo "Starting UCX server (maximum performance)..."
kubectl exec $SERVER_POD -- bash -c '
export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_IB_RX_INLINE=0
export UCX_IB_TX_INLINE_RESP=0
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_REG_METHODS=rcache,odp
export UCX_IB_RCACHE_MEM_PRIO=1000
ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 100 -w 64 -p 12348 > /tmp/server_max.log 2>&1 &
sleep 5
'

# Run client test with maximum performance settings
echo "Running client test (maximum performance)..."
kubectl exec $CLIENT_POD -- bash -c "
export UCX_TLS=ib,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_IB_NUM_PATHS=32
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_GID_INDEX=auto
export UCX_IB_MLX5_DEVX=y
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_IB_RX_INLINE=0
export UCX_IB_TX_INLINE_RESP=0
export UCX_RC_FC_ENABLE=n
export UCX_DC_MLX5_FC_ENABLE=n
export UCX_IB_REG_METHODS=rcache,odp
export UCX_IB_RCACHE_MEM_PRIO=1000
ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 100 -w 64 -p 12348 $SERVER_IP 2>&1 | tee /tmp/client_max.log
" | tail -10

# Kill server
kubectl exec $SERVER_POD -- pkill ucx_perftest 2>/dev/null || true

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Multi-NIC UCX Tests Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "1. Single NIC baseline test completed"
echo "2. Multi-path configuration (32 paths) tested"
echo "3. Rail configuration (32 rails) tested"
echo "4. Maximum performance configuration tested"
echo ""
echo "To view detailed logs:"
echo "  kubectl exec $SERVER_POD -- cat /tmp/server_*.log"
echo "  kubectl exec $CLIENT_POD -- cat /tmp/client_*.log"
echo ""
echo "Expected performance with 32 NICs:"
echo "  - Single NIC: ~285 GB/s"
echo "  - 32 NICs aggregate: ~9 TB/s theoretical maximum"
echo ""