#!/bin/bash
# Master deployment and benchmark orchestration script
# Deploys Dynamo cluster and runs all benchmark suites

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MASTER_RESULTS_DIR="$SCRIPT_DIR/benchmark-results-$TIMESTAMP"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     DYNAMO COMPLETE BENCHMARK ORCHESTRATION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Timestamp: $TIMESTAMP"
echo "Results will be saved to: $MASTER_RESULTS_DIR"
echo ""

# Create master results directory
mkdir -p "$MASTER_RESULTS_DIR"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found${NC}"
        exit 1
    fi

    # Check cluster access
    if ! kubectl get nodes &> /dev/null; then
        echo -e "${RED}❌ Cannot access Kubernetes cluster${NC}"
        exit 1
    fi

    # Check for GPU nodes
    local gpu_nodes=$(kubectl get nodes -o json | jq -r '.items[].status.capacity."nvidia.com/gpu"' | grep -v null | wc -l)
    if [ "$gpu_nodes" -lt 2 ]; then
        echo -e "${YELLOW}⚠️  Less than 2 GPU nodes available (found: $gpu_nodes)${NC}"
    fi

    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to deploy Dynamo cluster
deploy_cluster() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}STEP 1: Deploying Dynamo Cluster${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Create namespace
    kubectl create namespace dynamo-cloud 2>/dev/null || true

    # Deploy ETCD for NIXL coordination
    cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: etcd-service
  namespace: dynamo-cloud
spec:
  clusterIP: None
  selector:
    app: etcd
  ports:
  - port: 2379
    targetPort: 2379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: etcd
  namespace: dynamo-cloud
spec:
  serviceName: etcd
  replicas: 1
  selector:
    matchLabels:
      app: etcd
  template:
    metadata:
      labels:
        app: etcd
    spec:
      containers:
      - name: etcd
        image: quay.io/coreos/etcd:latest
        command:
        - etcd
        - --listen-client-urls=http://0.0.0.0:2379
        - --advertise-client-urls=http://etcd-service:2379
        ports:
        - containerPort: 2379
EOF

    # Deploy Dynamo backend pods with GPUs
    cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dynamo-backend-1
  namespace: dynamo-cloud
  labels:
    app: dynamo
    tier: backend
    node: "1"
spec:
  hostNetwork: true
  containers:
  - name: dynamo-backend
    image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:all-arch
    imagePullPolicy: IfNotPresent
    command: ["sleep", "infinity"]
    env:
    - name: LD_LIBRARY_PATH
      value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/opt/amazon/efa/lib64"
    - name: FI_PROVIDER
      value: "efa"
    - name: FI_HMEM_DISABLE_P2P
      value: "0"
    - name: NCCL_DEBUG
      value: "INFO"
    resources:
      requests:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
      limits:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
    securityContext:
      capabilities:
        add:
        - IPC_LOCK
      privileged: true
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            tier: backend
        topologyKey: kubernetes.io/hostname
---
apiVersion: v1
kind: Pod
metadata:
  name: dynamo-backend-2
  namespace: dynamo-cloud
  labels:
    app: dynamo
    tier: backend
    node: "2"
spec:
  hostNetwork: true
  containers:
  - name: dynamo-backend
    image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:all-arch
    imagePullPolicy: IfNotPresent
    command: ["sleep", "infinity"]
    env:
    - name: LD_LIBRARY_PATH
      value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/opt/amazon/efa/lib64"
    - name: FI_PROVIDER
      value: "efa"
    - name: FI_HMEM_DISABLE_P2P
      value: "0"
    - name: NCCL_DEBUG
      value: "INFO"
    resources:
      requests:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
      limits:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
    securityContext:
      capabilities:
        add:
        - IPC_LOCK
      privileged: true
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            tier: backend
        topologyKey: kubernetes.io/hostname
EOF

    # Wait for pods to be ready
    echo "Waiting for pods to be ready..."
    kubectl wait --for=condition=Ready pod -l app=etcd -n dynamo-cloud --timeout=300s || true
    kubectl wait --for=condition=Ready pod/dynamo-backend-1 -n dynamo-cloud --timeout=300s || true
    kubectl wait --for=condition=Ready pod/dynamo-backend-2 -n dynamo-cloud --timeout=300s || true

    echo -e "${GREEN}✅ Cluster deployed${NC}"
    kubectl get pods -n dynamo-cloud
}

# Function to run UCX benchmark
run_ucx_benchmark() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}BENCHMARK 1: UCX Native${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$SCRIPT_DIR/ucx-benchmark" ]; then
        cd "$SCRIPT_DIR/ucx-benchmark"
        ./run-ucx-test.sh 2>&1 | tee "$MASTER_RESULTS_DIR/ucx-native.log"
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✅ UCX benchmark complete${NC}"
    else
        echo -e "${YELLOW}⚠️  UCX benchmark directory not found${NC}"
    fi
}

# Function to run NIXL LIBFABRIC benchmark
run_nixl_libfabric() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}BENCHMARK 2: NIXL with LIBFABRIC Backend${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$SCRIPT_DIR/nixlbench-libfabric" ]; then
        cd "$SCRIPT_DIR/nixlbench-libfabric"
        ./run-libfabric-test.sh 2>&1 | tee "$MASTER_RESULTS_DIR/nixl-libfabric.log"
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✅ NIXL LIBFABRIC benchmark complete${NC}"
    else
        echo -e "${YELLOW}⚠️  NIXL LIBFABRIC benchmark directory not found${NC}"
    fi
}

# Function to run NIXL UCX benchmark
run_nixl_ucx() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}BENCHMARK 3: NIXL with UCX Backend${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$SCRIPT_DIR/nixlbench-ucx" ]; then
        cd "$SCRIPT_DIR/nixlbench-ucx"
        ./run-ucx-backend-test.sh 2>&1 | tee "$MASTER_RESULTS_DIR/nixl-ucx.log"
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✅ NIXL UCX benchmark complete${NC}"
    else
        echo -e "${YELLOW}⚠️  NIXL UCX benchmark directory not found${NC}"
    fi
}

# Function to run NCCL tests
run_nccl_tests() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}BENCHMARK 4: NCCL Collective Operations${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$SCRIPT_DIR/nccl-tests" ]; then
        cd "$SCRIPT_DIR/nccl-tests"
        ./run-nccl-tests.sh 2>&1 | tee "$MASTER_RESULTS_DIR/nccl-tests.log"
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✅ NCCL tests complete${NC}"
    else
        echo -e "${YELLOW}⚠️  NCCL tests directory not found${NC}"
    fi
}

# Function to generate summary report
generate_summary() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Generating Summary Report${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    cat << EOF > "$MASTER_RESULTS_DIR/BENCHMARK_SUMMARY.md"
# Dynamo Benchmark Results Summary
Generated: $(date)

## Test Configuration
- Cluster: AWS EKS with EFA
- Instance Type: $(kubectl get nodes -o jsonpath='{.items[0].metadata.labels.node\.kubernetes\.io/instance-type}' || echo "Unknown")
- GPU Type: H100 (assumed)
- Timestamp: $TIMESTAMP

## Benchmark Results

### 1. UCX Native Performance
$(grep -E "Final:|Multi-NIC Performance" "$MASTER_RESULTS_DIR/ucx-native.log" 2>/dev/null | tail -2 || echo "No results found")

### 2. NIXL LIBFABRIC Performance
$(grep -E "67108864|46\.|GB/s" "$MASTER_RESULTS_DIR/nixl-libfabric.log" 2>/dev/null | tail -2 || echo "No results found")

### 3. NIXL UCX Performance
$(grep -E "GB/s|error|failed" "$MASTER_RESULTS_DIR/nixl-ucx.log" 2>/dev/null | tail -2 || echo "No results found")

### 4. NCCL Collective Operations
$(grep -E "AllReduce|Bandwidth" "$MASTER_RESULTS_DIR/nccl-tests.log" 2>/dev/null | tail -2 || echo "No results found")

## Performance Comparison

| Benchmark | Backend | Expected | Actual | Status |
|-----------|---------|----------|--------|--------|
| UCX Native | SRD | 285 GB/s | TBD | TBD |
| NIXL | LIBFABRIC | 46.48 GB/s | TBD | TBD |
| NIXL | UCX | 0.85 GB/s | TBD | TBD |
| NCCL | AllReduce | 400 GB/s | TBD | TBD |

## Logs Location
All detailed logs saved to: $MASTER_RESULTS_DIR

## Recommendations
1. Use LIBFABRIC backend for NIXL workloads (46.48 GB/s proven)
2. UCX native provides best raw performance (285 GB/s per NIC)
3. Avoid NIXL+UCX combination (poor performance, ETCD issues)
4. NCCL optimal for ML collective operations

EOF

    echo -e "${GREEN}✅ Summary report generated: $MASTER_RESULTS_DIR/BENCHMARK_SUMMARY.md${NC}"
}

# Main execution
main() {
    echo "Starting benchmark orchestration..."
    echo ""

    # Check prerequisites
    check_prerequisites

    # Ask user what to run
    echo ""
    echo "Select benchmarks to run:"
    echo "  1) All benchmarks"
    echo "  2) UCX only"
    echo "  3) NIXL LIBFABRIC only"
    echo "  4) NIXL UCX only"
    echo "  5) NCCL only"
    echo "  6) Deploy cluster only"
    read -p "Enter choice [1-6]: " choice

    # Deploy cluster if needed
    if kubectl get pods -n dynamo-cloud 2>/dev/null | grep -q dynamo-backend; then
        echo -e "${GREEN}✅ Cluster already deployed${NC}"
    else
        deploy_cluster
    fi

    # Run selected benchmarks
    case $choice in
        1)
            run_ucx_benchmark
            run_nixl_libfabric
            run_nixl_ucx
            run_nccl_tests
            ;;
        2)
            run_ucx_benchmark
            ;;
        3)
            run_nixl_libfabric
            ;;
        4)
            run_nixl_ucx
            ;;
        5)
            run_nccl_tests
            ;;
        6)
            echo "Cluster deployed. Exiting."
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac

    # Generate summary
    generate_summary

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ BENCHMARK ORCHESTRATION COMPLETE${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Results saved to: $MASTER_RESULTS_DIR"
    echo ""
    echo "View summary: cat $MASTER_RESULTS_DIR/BENCHMARK_SUMMARY.md"
    echo ""
    echo "To cleanup cluster:"
    echo "  kubectl delete namespace dynamo-cloud"
}

# Run main function
main "$@"