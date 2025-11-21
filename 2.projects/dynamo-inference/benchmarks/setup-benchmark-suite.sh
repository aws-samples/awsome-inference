#!/bin/bash
# Setup script to create the complete benchmark suite structure

set -e

BENCHMARK_DIR="/home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks"

echo "═══════════════════════════════════════════════════════════════"
echo "     DYNAMO BENCHMARK SUITE SETUP"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Create directory structure
echo "Creating benchmark directory structure..."
mkdir -p "$BENCHMARK_DIR"/{ucx-benchmark,nixlbench-libfabric,nixlbench-ucx,dynamo-cluster}/{results,logs}
mkdir -p "$BENCHMARK_DIR"/dynamo-cluster/helper-scripts

echo "✓ Directory structure created"

# ============================================================================
# UCX BENCHMARK SETUP
# ============================================================================
echo ""
echo "Setting up UCX benchmark..."

cat << 'EOF' > "$BENCHMARK_DIR/ucx-benchmark/run-ucx-test.sh"
#!/bin/bash
# Native UCX Perftest Benchmark
# Expected: 285 GB/s per NIC, up to 9 TB/s with 32 NICs

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     UCX NATIVE PERFTEST BENCHMARK"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./results/ucx-test-$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

# Get pod IPs
POD1=$(kubectl get pod dynamo-backend-1 -n dynamo-cloud -o jsonpath='{.metadata.name}' 2>/dev/null || echo "dynamo-backend-1")
POD2=$(kubectl get pod dynamo-backend-2 -n dynamo-cloud -o jsonpath='{.metadata.name}' 2>/dev/null || echo "dynamo-backend-2")
POD1_IP=$(kubectl get pod $POD1 -n dynamo-cloud -o jsonpath='{.status.podIP}')

echo "Server Pod: $POD1 (IP: $POD1_IP)"
echo "Client Pod: $POD2"
echo ""

# Test 1: Single NIC baseline
echo "Test 1: Single NIC Baseline"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl exec $POD1 -n dynamo-cloud -- bash -c '
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=rdmap113s0:1
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 100000000 -n 10 -p 12345
' > "$RESULTS_DIR/server-single.log" 2>&1 &

SERVER_PID=$!
sleep 3

kubectl exec $POD2 -n dynamo-cloud -- bash -c "
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=rdmap113s0:1
CUDA_VISIBLE_DEVICES=0 ucx_perftest $POD1_IP -t ucp_put_bw -m cuda -s 100000000 -n 10 -p 12345
" | tee "$RESULTS_DIR/client-single.log"

kill $SERVER_PID 2>/dev/null || true

# Test 2: Multi-NIC with rails
echo ""
echo "Test 2: Multi-NIC with 32 Rails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl exec $POD1 -n dynamo-cloud -- bash -c '
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_RNDV_SCHEME=put_rail
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p 12346
' > "$RESULTS_DIR/server-multi.log" 2>&1 &

SERVER_PID=$!
sleep 5

kubectl exec $POD2 -n dynamo-cloud -- bash -c "
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_RNDV_SCHEME=put_rail
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest $POD1_IP -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p 12346
" | tee "$RESULTS_DIR/client-multi.log"

kill $SERVER_PID 2>/dev/null || true

# Extract results
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "RESULTS SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Single NIC Performance:"
grep -E "Final:|100000000" "$RESULTS_DIR/client-single.log" | tail -1
echo ""
echo "Multi-NIC Performance (32 rails):"
grep -E "Final:|8589934592" "$RESULTS_DIR/client-multi.log" | tail -1
echo ""
echo "Full results saved to: $RESULTS_DIR"
EOF

# ============================================================================
# NIXLBENCH LIBFABRIC SETUP
# ============================================================================
echo "Setting up NIXL LIBFABRIC benchmark..."

cat << 'EOF' > "$BENCHMARK_DIR/nixlbench-libfabric/run-libfabric-test.sh"
#!/bin/bash
# NIXL Benchmark with LIBFABRIC Backend
# Expected: 46.48 GB/s (proven configuration)

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     NIXL BENCHMARK - LIBFABRIC BACKEND"
echo "     Expected: 46.48 GB/s"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./results/libfabric-test-$TIMESTAMP"
BENCHMARK_GROUP="libfab-$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

# Get ETCD endpoint
ETCD_IP=$(kubectl get pod dynamo-platform-etcd-0 -n dynamo-cloud -o jsonpath='{.status.podIP}' 2>/dev/null || echo "10.1.25.101")
echo "ETCD IP: $ETCD_IP"

# Clean ETCD
echo "Cleaning ETCD state..."
kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
sleep 2

# Get pods
POD1="dynamo-backend-1"
POD2="dynamo-backend-2"

echo "Starting benchmark group: $BENCHMARK_GROUP"
echo ""

# Critical: Start POD2 first (becomes rank 0 - target)
echo "Starting $POD2 (target)..."
kubectl exec $POD2 -n dynamo-cloud -- bash -c "
export FI_HMEM_DISABLE_P2P=0
export FI_PROVIDER=efa
export FI_LOG_LEVEL=warn
nixlbench \
  --etcd_endpoints http://$ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend LIBFABRIC \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5
" > "$RESULTS_DIR/node2.log" 2>&1 &

NODE2_PID=$!
echo "Node2 started (PID: $NODE2_PID)"

# CRITICAL: Wait for node2 to register
echo "Waiting 10 seconds for node2 to register with ETCD..."
sleep 10

# Start POD1 (becomes rank 1 - initiator)
echo "Starting $POD1 (initiator)..."
kubectl exec $POD1 -n dynamo-cloud -- bash -c "
export FI_HMEM_DISABLE_P2P=0
export FI_PROVIDER=efa
export FI_LOG_LEVEL=warn
nixlbench \
  --etcd_endpoints http://$ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend LIBFABRIC \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5
" 2>&1 | tee "$RESULTS_DIR/node1.log"

# Wait for node2 to complete
wait $NODE2_PID

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "RESULTS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
grep -E "GB/s|67108864" "$RESULTS_DIR/node1.log" | tail -5 || echo "Check logs for results"
echo ""
echo "Full results saved to: $RESULTS_DIR"
echo "Expected: 46.48 GB/s for 67MB blocks"
EOF

# ============================================================================
# NIXLBENCH UCX SETUP
# ============================================================================
echo "Setting up NIXL UCX benchmark..."

cat << 'EOF' > "$BENCHMARK_DIR/nixlbench-ucx/run-ucx-backend-test.sh"
#!/bin/bash
# NIXL Benchmark with UCX Backend
# Note: May fail with "target uri is not valid" error
# Expected: 0.85 GB/s (known limitation)

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     NIXL BENCHMARK - UCX BACKEND"
echo "     Note: May fail with ETCD URI error"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./results/ucx-test-$TIMESTAMP"
BENCHMARK_GROUP="ucx-$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

# Get ETCD endpoint
ETCD_IP=$(kubectl get pod dynamo-platform-etcd-0 -n dynamo-cloud -o jsonpath='{.status.podIP}' 2>/dev/null || echo "10.1.25.101")
echo "ETCD IP: $ETCD_IP"

# Clean ETCD
echo "Cleaning ETCD state..."
kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
sleep 2

# Get pods
POD1="dynamo-backend-1"
POD2="dynamo-backend-2"

echo "Starting benchmark group: $BENCHMARK_GROUP"
echo "Using DRAM to avoid VRAM URI issues..."
echo ""

# Try with DRAM instead of VRAM to avoid URI issues
kubectl exec $POD1 -n dynamo-cloud -- bash -c "
nixlbench \
  --etcd_endpoints http://$ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend UCX \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --warmup_iter 5
" > "$RESULTS_DIR/node1.log" 2>&1 &

kubectl exec $POD2 -n dynamo-cloud -- bash -c "
nixlbench \
  --etcd_endpoints http://$ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend UCX \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --warmup_iter 5
" > "$RESULTS_DIR/node2.log" 2>&1 &

wait

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "RESULTS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
grep -E "GB/s|error|failed" "$RESULTS_DIR"/*.log | tail -10 || echo "Test may have failed - check logs"
echo ""
echo "Full results saved to: $RESULTS_DIR"
echo "Expected: 0.85 GB/s or ETCD URI error"
EOF

# ============================================================================
# CLUSTER DEPLOYMENT SCRIPT
# ============================================================================
echo "Creating cluster deployment script..."

# Copy the working ETCD deployment from nixl-efa-benchmark
cp /home/ubuntu/nixl-efa-benchmark/kubernetes/etcd-deployment.yaml "$BENCHMARK_DIR/dynamo-cluster/etcd-service.yaml" 2>/dev/null || \
cat << 'EOF' > "$BENCHMARK_DIR/dynamo-cluster/etcd-service.yaml"
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

cat << 'EOF' > "$BENCHMARK_DIR/deploy-cluster.sh"
#!/bin/bash
# Deploy the complete Dynamo cluster with benchmark pods

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     DEPLOYING DYNAMO BENCHMARK CLUSTER"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Create namespace
kubectl create namespace dynamo-cloud 2>/dev/null || true

# Deploy ETCD
echo "Deploying ETCD coordination service..."
kubectl apply -f dynamo-cluster/etcd-service.yaml

# Deploy Dynamo backend pods
echo "Deploying Dynamo backend pods..."
kubectl apply -f dynamo-cluster/dynamo-deployment.yaml

# Wait for pods
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=etcd -n dynamo-cloud --timeout=300s
kubectl wait --for=condition=Ready pod -l tier=backend -n dynamo-cloud --timeout=300s

echo ""
echo "✅ Cluster deployed successfully!"
echo ""
kubectl get pods -n dynamo-cloud
echo ""
EOF

# ============================================================================
# MASTER RUN SCRIPT
# ============================================================================
echo "Creating master run script..."

cat << 'EOF' > "$BENCHMARK_DIR/run-all-benchmarks.sh"
#!/bin/bash
# Master script to run all benchmarks in sequence

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     DYNAMO COMPLETE BENCHMARK SUITE"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./results-summary-$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

# Deploy cluster if needed
if ! kubectl get pods -n dynamo-cloud | grep -q dynamo-backend; then
    echo "Deploying cluster..."
    ./deploy-cluster.sh
fi

# Run benchmarks
echo ""
echo "Starting benchmark suite..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. UCX Native
echo "Running UCX native benchmark..."
cd ucx-benchmark
./run-ucx-test.sh | tee "$RESULTS_DIR/ucx-native.log"
cd ..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2. NIXL LIBFABRIC
echo "Running NIXL LIBFABRIC benchmark..."
cd nixlbench-libfabric
./run-libfabric-test.sh | tee "$RESULTS_DIR/nixl-libfabric.log"
cd ..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 3. NIXL UCX (may fail)
echo "Running NIXL UCX benchmark..."
cd nixlbench-ucx
./run-ucx-backend-test.sh | tee "$RESULTS_DIR/nixl-ucx.log"
cd ..

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "BENCHMARK SUITE COMPLETE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Results Summary:"
echo "----------------"
echo "UCX Native:"
grep -E "Final:|Multi-NIC" "$RESULTS_DIR/ucx-native.log" | tail -2

echo ""
echo "NIXL LIBFABRIC:"
grep -E "67108864|46\." "$RESULTS_DIR/nixl-libfabric.log" | tail -1

echo ""
echo "NIXL UCX:"
grep -E "GB/s|error" "$RESULTS_DIR/nixl-ucx.log" | tail -1

echo ""
echo "Full results saved to: $RESULTS_DIR"
EOF

# Make all scripts executable
chmod +x "$BENCHMARK_DIR"/*.sh
chmod +x "$BENCHMARK_DIR"/ucx-benchmark/*.sh
chmod +x "$BENCHMARK_DIR"/nixlbench-libfabric/*.sh
chmod +x "$BENCHMARK_DIR"/nixlbench-ucx/*.sh

echo ""
echo "✅ Benchmark suite setup complete!"
echo ""
echo "Directory structure created at: $BENCHMARK_DIR"
echo ""
echo "To run the complete benchmark suite:"
echo "  cd $BENCHMARK_DIR"
echo "  ./deploy-cluster.sh    # Deploy the cluster"
echo "  ./run-all-benchmarks.sh # Run all benchmarks"
echo ""
echo "Or run individual benchmarks:"
echo "  cd ucx-benchmark && ./run-ucx-test.sh"
echo "  cd nixlbench-libfabric && ./run-libfabric-test.sh"
echo "  cd nixlbench-ucx && ./run-ucx-backend-test.sh"
echo ""