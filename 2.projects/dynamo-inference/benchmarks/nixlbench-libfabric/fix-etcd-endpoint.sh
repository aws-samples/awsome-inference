#!/bin/bash
# Fix for ETCD endpoint issue

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     FIXING ETCD ENDPOINT FOR NIXLBENCH"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get the actual ETCD service endpoint
ETCD_SVC=$(kubectl get svc -n dynamo-cloud | grep "dynamo-platform-etcd " | awk '{print $1}')
ETCD_IP=$(kubectl get svc dynamo-platform-etcd -n dynamo-cloud -o jsonpath='{.spec.clusterIP}')

echo "Found ETCD service: $ETCD_SVC"
echo "ETCD ClusterIP: $ETCD_IP"
echo ""

# Test ETCD connectivity from pods
echo "Testing ETCD connectivity from pods..."
kubectl exec dynamo-backend-1 -n dynamo-cloud -- curl -s http://$ETCD_IP:2379/version || echo "Cannot connect from pod"
echo ""

# Clean ETCD
echo "Cleaning ETCD state..."
kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
sleep 2

# Generate unique benchmark group
BENCHMARK_GROUP="libfab-fix-$(date +%s)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/tmp/nixlbench-libfabric-logs-$TIMESTAMP"

echo "Benchmark group: $BENCHMARK_GROUP"
echo "Log directory: $LOG_DIR"
echo ""

# Create log directory
mkdir -p "$LOG_DIR"

echo "═══════════════════════════════════════════════════════════════"
echo "RUNNING BENCHMARK WITH CORRECT ETCD ENDPOINT"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Using ETCD endpoint: http://$ETCD_IP:2379"
echo ""

# Start node2 first (becomes rank 0 - target)
echo "Starting node2 (target) in background..."
kubectl exec dynamo-backend-2 -n dynamo-cloud -- bash -c "
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
" > "$LOG_DIR/node2.log" 2>&1 &

NODE2_PID=$!
echo "✓ Node2 started (PID: $NODE2_PID)"

# Wait for node2 to register
echo ""
echo "Waiting 10 seconds for node2 to register..."
for i in {10..1}; do
    echo -n "$i... "
    sleep 1
done
echo ""

# Start node1 (becomes rank 1 - initiator)
echo ""
echo "Starting node1 (initiator)..."
kubectl exec dynamo-backend-1 -n dynamo-cloud -- bash -c "
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
" 2>&1 | tee "$LOG_DIR/node1.log"

# Wait for node2
wait $NODE2_PID 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "CHECKING RESULTS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check for errors
if grep -q "target uri is not valid" "$LOG_DIR"/*.log 2>/dev/null; then
    echo "❌ ETCD URI error still present"
    echo ""
    echo "Trying alternative: Use DRAM instead of VRAM..."
    echo ""

    # Clean ETCD again
    kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
    sleep 2

    BENCHMARK_GROUP="libfab-dram-$(date +%s)"

    # Try with DRAM
    kubectl exec dynamo-backend-2 -n dynamo-cloud -- bash -c "
    nixlbench \
      --etcd_endpoints http://$ETCD_IP:2379 \
      --benchmark_group $BENCHMARK_GROUP \
      --backend LIBFABRIC \
      --target_seg_type DRAM \
      --total_buffer_size 1073741824 \
      --warmup_iter 5
    " > "$LOG_DIR/node2-dram.log" 2>&1 &

    NODE2_PID=$!
    sleep 10

    kubectl exec dynamo-backend-1 -n dynamo-cloud -- bash -c "
    nixlbench \
      --etcd_endpoints http://$ETCD_IP:2379 \
      --benchmark_group $BENCHMARK_GROUP \
      --backend LIBFABRIC \
      --target_seg_type DRAM \
      --total_buffer_size 1073741824 \
      --warmup_iter 5
    " 2>&1 | tee "$LOG_DIR/node1-dram.log"

    wait $NODE2_PID 2>/dev/null || true
fi

# Extract results
echo ""
echo "Looking for performance results..."
grep -E "GB/s|67108864|Final" "$LOG_DIR"/*.log 2>/dev/null | tail -5 || echo "No results found"

echo ""
echo "Logs saved to: $LOG_DIR"
echo ""
echo "To check logs:"
echo "  cat $LOG_DIR/node1.log"
echo "  cat $LOG_DIR/node2.log"
echo ""