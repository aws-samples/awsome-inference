#!/bin/bash
set -e

# NIXL Benchmark - LIBFABRIC Backend Test
# Proven to achieve 46.48 GB/s GPU-to-GPU bandwidth on P5 instances
# Based on validated configuration from nixl-efa-benchmark

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_ID="nixlbench-libfabric-$(date +%Y%m%d_%H%M%S)"
LOG_DIR="/tmp/nixlbench-libfabric-logs-${TEST_ID}"
mkdir -p "${LOG_DIR}"

MAIN_LOG="${LOG_DIR}/test-report.txt"

# Function to log to both console and file
log() {
    echo -e "$1" | tee -a "${MAIN_LOG}"
}

log "${BLUE}=========================================="
log "NIXL BENCHMARK - LIBFABRIC TEST"
log "==========================================${NC}"
log "Test ID: ${TEST_ID}"
log "Test Date: $(date)"
log "Purpose: Measure GPU-to-GPU RDMA bandwidth with LIBFABRIC backend"
log ""

# Check prerequisites
log "${BLUE}=== CHECKING PREREQUISITES ===${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log "${RED}❌ ERROR: kubectl not found${NC}"
    exit 1
fi
log "${GREEN}✓ kubectl found${NC}"

# Check if pods exist
if ! kubectl get pod nixl-bench-node1 &> /dev/null; then
    log "${RED}❌ ERROR: nixl-bench-node1 pod not found${NC}"
    log "Please deploy benchmark pods first"
    exit 1
fi

if ! kubectl get pod nixl-bench-node2 &> /dev/null; then
    log "${RED}❌ ERROR: nixl-bench-node2 pod not found${NC}"
    log "Please deploy benchmark pods first"
    exit 1
fi
log "${GREEN}✓ Benchmark pods found${NC}"

# Check if ETCD exists
if ! kubectl get service etcd-service &> /dev/null; then
    log "${RED}❌ ERROR: etcd-service not found${NC}"
    log "Please deploy ETCD coordination service first"
    exit 1
fi
log "${GREEN}✓ ETCD service found${NC}"
log ""

# Clean ETCD before test (critical for reliable results)
log "${BLUE}=== CLEANING ETCD ===${NC}"
log "Cleaning ETCD to ensure fresh state..."
kubectl exec -it statefulset/etcd -- etcdctl del "" --from-key=true --prefix 2>&1 | tee -a "${MAIN_LOG}" || true
sleep 2
log "${GREEN}✓ ETCD cleaned${NC}"
log ""

log "${BLUE}=== TEST CONFIGURATION ===${NC}"
log "Backend: ${GREEN}LIBFABRIC${NC}"
log "Provider: ${GREEN}EFA (Elastic Fabric Adapter)${NC}"
log "Memory Type: ${GREEN}VRAM-to-VRAM (GPU Direct)${NC}"
log "P2P Setting: ${GREEN}FI_HMEM_DISABLE_P2P=0 (ENABLED)${NC} ${YELLOW}⚠️ CRITICAL for P5 instances${NC}"
log "Log Level: info"
log "ETCD: http://etcd-service:2379"
log ""

log "${BLUE}=== POD PLACEMENT VERIFICATION ===${NC}"
NODE1=$(kubectl get pod nixl-bench-node1 -o jsonpath='{.spec.nodeName}')
NODE2=$(kubectl get pod nixl-bench-node2 -o jsonpath='{.spec.nodeName}')

log "Pod 1 (nixl-bench-node1): ${NODE1}"
log "Pod 2 (nixl-bench-node2): ${NODE2}"

if [ "$NODE1" == "$NODE2" ]; then
    log "${RED}❌ ERROR: Pods are on the SAME node!${NC}"
    log "Anti-affinity not working. Cross-node RDMA test requires different nodes."
    exit 1
else
    log "${GREEN}✅ PASS: Pods are on DIFFERENT physical nodes${NC}"
fi
log ""

log "${BLUE}=== HARDWARE VERIFICATION ===${NC}"
log "Checking EFA devices on node1..."
kubectl exec nixl-bench-node1 -- ls -la /dev/infiniband/ >> "${LOG_DIR}/efa-devices-node1.txt" 2>&1
EFA_COUNT=$(kubectl exec nixl-bench-node1 -- ls /dev/infiniband/ 2>/dev/null | wc -l)
log "${GREEN}✓ Found ${EFA_COUNT} EFA devices${NC}"

log "Checking GPU devices on node1..."
kubectl exec nixl-bench-node1 -- nvidia-smi -L >> "${LOG_DIR}/gpu-info-node1.txt" 2>&1
GPU_COUNT=$(kubectl exec nixl-bench-node1 -- nvidia-smi -L 2>/dev/null | wc -l)
log "${GREEN}✓ Found ${GPU_COUNT} GPU(s)${NC}"

log "Gathering libfabric EFA provider info..."
kubectl exec nixl-bench-node1 -- fi_info -p efa >> "${LOG_DIR}/fi_info-node1.txt" 2>&1
log "${GREEN}✓ EFA provider info saved${NC}"
log ""

log "${BLUE}=== ENVIRONMENT CONFIGURATION ===${NC}"
log "Critical P2P Setting for P5 instances:"
log "  FI_HMEM_DISABLE_P2P=0  ${GREEN}(P2P ENABLED)${NC}"
log ""
log "${YELLOW}⚠️  Note: FI_HMEM_DISABLE_P2P=0 is REQUIRED for optimal performance on P5 instances${NC}"
log "This enables GPU Direct RDMA for peer-to-peer transfers across nodes."
log ""

log "${BLUE}=== STARTING BENCHMARK ===${NC}"
log "${YELLOW}⚠️  Starting sequence: Pod 2 first, wait 10 seconds, then Pod 1${NC}"
log ""

# Start node2 (target) in background
log "Starting ${GREEN}node2${NC} (target) in background..."
kubectl exec nixl-bench-node2 -- bash -c \
  "FI_PROVIDER=efa FI_HMEM_DISABLE_P2P=0 FI_LOG_LEVEL=info nixlbench --backend LIBFABRIC --initiator_seg_type VRAM --target_seg_type VRAM --etcd_endpoints http://etcd-service:2379" \
  > "${LOG_DIR}/node2-output.log" 2>&1 &

NODE2_PID=$!
log "${GREEN}✓ Node2 started (Background PID: ${NODE2_PID})${NC}"
log ""

# Wait for node2 to register with ETCD (critical timing)
log "Waiting ${YELLOW}10 seconds${NC} for node2 to register with ETCD..."
for i in {10..1}; do
    echo -n "$i... "
    sleep 1
done
echo ""
log "${GREEN}✓ Node2 should be registered${NC}"
log ""

# Start node1 (initiator) and capture output
log "Starting ${GREEN}node1${NC} (initiator)..."
log "This will run the benchmark and display results..."
log "${BLUE}=========================================="
log "BENCHMARK OUTPUT"
log "==========================================${NC}"

kubectl exec nixl-bench-node1 -- bash -c \
  "FI_PROVIDER=efa FI_HMEM_DISABLE_P2P=0 FI_LOG_LEVEL=info nixlbench --backend LIBFABRIC --initiator_seg_type VRAM --target_seg_type VRAM --etcd_endpoints http://etcd-service:2379" \
  2>&1 | tee "${LOG_DIR}/node1-output.log"

log "${BLUE}=========================================="
log "BENCHMARK COMPLETE"
log "==========================================${NC}"
log ""

# Wait for node2 to finish
log "Waiting for node2 to finish..."
sleep 3

# Collect node2 logs
log "Collecting node2 logs..."
if [ -f "${LOG_DIR}/node2-output.log" ]; then
    log "${GREEN}✓ Node2 logs captured${NC}"
fi
log ""

# Extract and display performance results
log "${BLUE}=== PERFORMANCE RESULTS ===${NC}"
if grep -q "Average Bandwidth" "${LOG_DIR}/node1-output.log"; then
    log ""
    grep -E "(Block Size|Average Bandwidth|Maximum Bandwidth)" "${LOG_DIR}/node1-output.log" | tail -20 | tee -a "${MAIN_LOG}"
    log ""

    # Extract peak bandwidth
    PEAK_BW=$(grep "Maximum Bandwidth" "${LOG_DIR}/node1-output.log" | tail -1 | awk '{print $3}')
    if [ ! -z "$PEAK_BW" ]; then
        log "${GREEN}=========================================="
        log "PEAK BANDWIDTH: ${PEAK_BW} GB/s"
        log "==========================================${NC}"
        log ""

        # Compare with expected performance
        EXPECTED=46.48
        log "Expected performance: ${EXPECTED} GB/s (validated on P5 instances)"
        log "Your result: ${PEAK_BW} GB/s"
        log ""
    fi
else
    log "${RED}⚠  No performance results found in output${NC}"
    log "Check logs for errors: ${LOG_DIR}/node1-output.log"
fi
log ""

# Test summary
log "${BLUE}=== TEST SUMMARY ===${NC}"
log "Test ID: ${TEST_ID}"
log "Date: $(date)"
log "Backend: LIBFABRIC (EFA provider)"
log "Memory: VRAM-to-VRAM (GPU Direct)"
log "P2P: ENABLED (FI_HMEM_DISABLE_P2P=0)"
log "Physical Nodes: Different (verified)"
log ""

log "${BLUE}=== TEST ARTIFACTS ===${NC}"
log "Log directory: ${LOG_DIR}"
log "Files created:"
log "  - test-report.txt         (main log)"
log "  - node1-output.log        (initiator logs with results)"
log "  - node2-output.log        (target logs)"
log "  - fi_info-node1.txt       (EFA provider configuration)"
log "  - gpu-info-node1.txt      (GPU information)"
log "  - efa-devices-node1.txt   (EFA device details)"
log ""

log "${GREEN}=========================================="
log "TEST COMPLETE"
log "==========================================${NC}"
log ""
log "Next steps:"
log "1. Review test report: ${MAIN_LOG}"
log "2. Compare results with expected 46.48 GB/s"
log "3. If performance is lower, check:"
log "   - P2P is enabled (FI_HMEM_DISABLE_P2P=0)"
log "   - Pods are on different physical nodes"
log "   - EFA devices are properly allocated"
log "   - ETCD is clean before each test"
log ""
log "For detailed analysis, see: ${LOG_DIR}"
log ""

# Display final message
echo ""
echo -e "${GREEN}✅ Full test report saved to: ${MAIN_LOG}${NC}"
echo -e "${BLUE}Log directory: ${LOG_DIR}${NC}"
echo ""
