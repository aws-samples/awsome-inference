#!/bin/bash
# UCX Performance Test - Single NIC vs Multi-NIC (32 Rails)
# Based on working configuration that achieved 307 MB/s baseline
# Expected: 285 GB/s per NIC, up to 9 TB/s with 32 NICs

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESULTS_DIR="/home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks/ucx-benchmark/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${RESULTS_DIR}/ucx-test-${TIMESTAMP}.log"

# Test parameters
BUFFER_SIZE_8GB=8589934592  # 8GB for maximum throughput
BUFFER_SIZE_1GB=1073741824  # 1GB for comparison
ITERATIONS=50
WARMUP=20
SERVER_IP="10.1.238.41"  # Update this to your server pod IP
BASE_PORT=10100

# Ensure results directory exists
mkdir -p "${RESULTS_DIR}"

echo "════════════════════════════════════════════════════════════════"
echo "  UCX Performance Test Suite"
echo "  Baseline: 307 MB/s single NIC"
echo "  Expected: 285 GB/s per NIC, ~9 TB/s with 32 NICs"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}Results will be saved to: ${RESULT_FILE}${NC}"
echo ""

# Function to run a test
run_test() {
    local test_name="$1"
    local description="$2"
    shift 2
    local env_vars=("$@")

    echo "" | tee -a "${RESULT_FILE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "${RESULT_FILE}"
    echo -e "${GREEN}${test_name}${NC}" | tee -a "${RESULT_FILE}"
    echo "${description}" | tee -a "${RESULT_FILE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "${RESULT_FILE}"
    echo "" | tee -a "${RESULT_FILE}"

    # Print environment variables
    echo "Environment settings:" | tee -a "${RESULT_FILE}"
    for var in "${env_vars[@]}"; do
        echo "  export ${var}" | tee -a "${RESULT_FILE}"
    done
    echo "" | tee -a "${RESULT_FILE}"
}

# Function to display server command
show_server_command() {
    local port="$1"
    local test_name="$2"

    echo -e "${YELLOW}SERVER COMMAND (run on server pod first):${NC}" | tee -a "${RESULT_FILE}"
    echo "CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -p ${port}" | tee -a "${RESULT_FILE}"
    echo "" | tee -a "${RESULT_FILE}"
}

# Function to display client command
show_client_command() {
    local port="$1"
    local buffer_size="$2"
    local iterations="$3"
    local warmup="$4"

    echo -e "${YELLOW}CLIENT COMMAND (run on client pod after server is ready):${NC}" | tee -a "${RESULT_FILE}"
    echo "CUDA_VISIBLE_DEVICES=0 ucx_perftest ${SERVER_IP} -t ucp_put_bw -m cuda -s ${buffer_size} -n ${iterations} -w ${warmup} -p ${port}" | tee -a "${RESULT_FILE}"
    echo "" | tee -a "${RESULT_FILE}"
}

# Log test start time
echo "Test started at: $(date)" | tee "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"

# ============================================================================
# TEST 1: Single NIC Baseline (Known Working Configuration)
# ============================================================================
run_test \
    "Test 1: Single NIC Baseline" \
    "This is the proven working configuration (307 MB/s baseline)" \
    "UCX_TLS=srd,cuda_copy,cuda_ipc" \
    "UCX_NET_DEVICES=rdmap113s0:1"

show_server_command "${BASE_PORT}" "single-nic-baseline"

echo "On SERVER pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=rdmap113s0:1" | tee -a "${RESULT_FILE}"
show_server_command "${BASE_PORT}" "single-nic-baseline"

echo "On CLIENT pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=rdmap113s0:1" | tee -a "${RESULT_FILE}"
show_client_command "${BASE_PORT}" "${BUFFER_SIZE_1GB}" "10" "0"

echo -e "${BLUE}Press Enter after recording results to continue...${NC}"
read

# ============================================================================
# TEST 2: Multi-NIC with 32 Rails (1GB buffer)
# ============================================================================
run_test \
    "Test 2: Multi-NIC with 32 Rails (1GB buffer)" \
    "Testing multi-rail with UCX_MAX_RNDV_RAILS=32" \
    "UCX_TLS=srd,cuda_copy,cuda_ipc" \
    "UCX_NET_DEVICES=all" \
    "UCX_MAX_RNDV_RAILS=32" \
    "UCX_IB_NUM_PATHS=32"

PORT=$((BASE_PORT + 1))
show_server_command "${PORT}" "multi-nic-1gb"

echo "On SERVER pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_IB_NUM_PATHS=32" | tee -a "${RESULT_FILE}"
show_server_command "${PORT}" "multi-nic-1gb"

echo "On CLIENT pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_IB_NUM_PATHS=32" | tee -a "${RESULT_FILE}"
show_client_command "${PORT}" "${BUFFER_SIZE_1GB}" "10" "0"

echo -e "${BLUE}Press Enter after recording results to continue...${NC}"
read

# ============================================================================
# TEST 3: Multi-NIC with 32 Rails + GDR Copy (8GB buffer)
# ============================================================================
run_test \
    "Test 3: Multi-NIC with 32 Rails + GDR Copy (8GB buffer)" \
    "Maximum performance test with GPU Direct RDMA and 8GB transfers" \
    "UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" \
    "UCX_NET_DEVICES=all" \
    "UCX_MAX_RNDV_RAILS=32" \
    "UCX_IB_NUM_PATHS=32" \
    "UCX_RNDV_THRESH=8192" \
    "UCX_ZCOPY_THRESH=32768"

PORT=$((BASE_PORT + 2))
show_server_command "${PORT}" "multi-nic-8gb-gdr"

echo "On SERVER pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_IB_NUM_PATHS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_THRESH=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_ZCOPY_THRESH=32768" | tee -a "${RESULT_FILE}"
show_server_command "${PORT}" "multi-nic-8gb-gdr"

echo "On CLIENT pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_IB_NUM_PATHS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_THRESH=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_ZCOPY_THRESH=32768" | tee -a "${RESULT_FILE}"
show_client_command "${PORT}" "${BUFFER_SIZE_8GB}" "${ITERATIONS}" "${WARMUP}"

echo -e "${BLUE}Press Enter after recording results to continue...${NC}"
read

# ============================================================================
# TEST 4: Multi-NIC with SRD-Specific Optimizations (8GB buffer)
# ============================================================================
run_test \
    "Test 4: Multi-NIC with SRD-Specific Optimizations (8GB buffer)" \
    "Maximum performance with SRD queue length optimizations" \
    "UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" \
    "UCX_NET_DEVICES=all" \
    "UCX_MAX_RNDV_RAILS=32" \
    "UCX_MAX_EAGER_RAILS=32" \
    "UCX_IB_NUM_PATHS=32" \
    "UCX_SRD_TX_QUEUE_LEN=8192" \
    "UCX_SRD_RX_QUEUE_LEN=8192" \
    "UCX_SRD_MAX_NUM_EPS=256" \
    "UCX_RNDV_THRESH=8192" \
    "UCX_ZCOPY_THRESH=32768" \
    "UCX_WARN_UNUSED_ENV_VARS=n"

PORT=$((BASE_PORT + 3))
show_server_command "${PORT}" "multi-nic-srd-optimized"

echo "On SERVER pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_EAGER_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_IB_NUM_PATHS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_TX_QUEUE_LEN=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_RX_QUEUE_LEN=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_MAX_NUM_EPS=256" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_THRESH=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_ZCOPY_THRESH=32768" | tee -a "${RESULT_FILE}"
echo "export UCX_WARN_UNUSED_ENV_VARS=n" | tee -a "${RESULT_FILE}"
show_server_command "${PORT}" "multi-nic-srd-optimized"

echo "On CLIENT pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_EAGER_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_IB_NUM_PATHS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_TX_QUEUE_LEN=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_RX_QUEUE_LEN=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_MAX_NUM_EPS=256" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_THRESH=8192" | tee -a "${RESULT_FILE}"
echo "export UCX_ZCOPY_THRESH=32768" | tee -a "${RESULT_FILE}"
echo "export UCX_WARN_UNUSED_ENV_VARS=n" | tee -a "${RESULT_FILE}"
show_client_command "${PORT}" "${BUFFER_SIZE_8GB}" "${ITERATIONS}" "${WARMUP}"

echo -e "${BLUE}Press Enter after recording results to continue...${NC}"
read

# ============================================================================
# TEST 5: Multi-NIC with Rail Striping (8GB buffer)
# ============================================================================
run_test \
    "Test 5: Multi-NIC with Rail Striping (8GB buffer)" \
    "Testing put_rail scheme for optimal rail distribution" \
    "UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" \
    "UCX_NET_DEVICES=all" \
    "UCX_MAX_RNDV_RAILS=32" \
    "UCX_MAX_EAGER_RAILS=32" \
    "UCX_RNDV_SCHEME=put_rail" \
    "UCX_RNDV_THRESH=1024" \
    "UCX_SRD_SEG_SIZE=16384" \
    "UCX_WARN_UNUSED_ENV_VARS=n"

PORT=$((BASE_PORT + 4))
show_server_command "${PORT}" "multi-nic-rail-striping"

echo "On SERVER pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_EAGER_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_SCHEME=put_rail" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_THRESH=1024" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_SEG_SIZE=16384" | tee -a "${RESULT_FILE}"
echo "export UCX_WARN_UNUSED_ENV_VARS=n" | tee -a "${RESULT_FILE}"
show_server_command "${PORT}" "multi-nic-rail-striping"

echo "On CLIENT pod, run:" | tee -a "${RESULT_FILE}"
echo "export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy" | tee -a "${RESULT_FILE}"
echo "export UCX_NET_DEVICES=all" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_RNDV_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_MAX_EAGER_RAILS=32" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_SCHEME=put_rail" | tee -a "${RESULT_FILE}"
echo "export UCX_RNDV_THRESH=1024" | tee -a "${RESULT_FILE}"
echo "export UCX_SRD_SEG_SIZE=16384" | tee -a "${RESULT_FILE}"
echo "export UCX_WARN_UNUSED_ENV_VARS=n" | tee -a "${RESULT_FILE}"
show_client_command "${PORT}" "${BUFFER_SIZE_8GB}" "${ITERATIONS}" "${WARMUP}"

echo "" | tee -a "${RESULT_FILE}"
echo "════════════════════════════════════════════════════════════════" | tee -a "${RESULT_FILE}"
echo "  All Tests Complete!" | tee -a "${RESULT_FILE}"
echo "════════════════════════════════════════════════════════════════" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
echo "Test completed at: $(date)" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
echo "Results saved to: ${RESULT_FILE}" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
echo "Expected Performance Summary:" | tee -a "${RESULT_FILE}"
echo "  - Test 1 (Single NIC):           ~300 MB/s (baseline)" | tee -a "${RESULT_FILE}"
echo "  - Test 2 (Multi-NIC 1GB):        ~9-10 GB/s" | tee -a "${RESULT_FILE}"
echo "  - Test 3 (Multi-NIC 8GB + GDR):  ~285 GB/s (target)" | tee -a "${RESULT_FILE}"
echo "  - Test 4 (SRD Optimized):        ~285 GB/s (target)" | tee -a "${RESULT_FILE}"
echo "  - Test 5 (Rail Striping):        ~285 GB/s (target)" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
echo "Note: Actual performance depends on hardware and network topology" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
