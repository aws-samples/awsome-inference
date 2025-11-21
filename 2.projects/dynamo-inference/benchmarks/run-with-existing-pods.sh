#!/bin/bash
# Run benchmarks with existing nixl-bench pods

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     RUNNING BENCHMARKS WITH EXISTING PODS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get ETCD endpoint
ETCD_IP=$(kubectl get svc dynamo-platform-etcd -n dynamo-cloud -o jsonpath='{.spec.clusterIP}')
echo "ETCD IP: $ETCD_IP"

# Clean ETCD
echo "Cleaning ETCD state..."
kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
sleep 2

BENCHMARK_GROUP="test-$(date +%s)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/tmp/benchmark-logs-$TIMESTAMP"
mkdir -p "$LOG_DIR"

echo "Benchmark group: $BENCHMARK_GROUP"
echo ""

# Option 1: Try LIBFABRIC with DRAM (to avoid VRAM URI issues)
echo "═══════════════════════════════════════════════════════════════"
echo "TEST 1: LIBFABRIC with DRAM"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Starting nixl-bench-node2 (target)..."
kubectl exec nixl-bench-node2 -- bash -c "
export FI_HMEM_DISABLE_P2P=0
export FI_PROVIDER=efa
nixlbench \
  --etcd_endpoints http://$ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend LIBFABRIC \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --warmup_iter 5
" > "$LOG_DIR/libfabric-node2.log" 2>&1 &

NODE2_PID=$!
echo "Node2 started (PID: $NODE2_PID)"
sleep 10

echo "Starting nixl-bench-node1 (initiator)..."
kubectl exec nixl-bench-node1 -- bash -c "
export FI_HMEM_DISABLE_P2P=0
export FI_PROVIDER=efa
nixlbench \
  --etcd_endpoints http://$ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend LIBFABRIC \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --warmup_iter 5
" 2>&1 | tee "$LOG_DIR/libfabric-node1.log"

wait $NODE2_PID 2>/dev/null || true

echo ""
echo "LIBFABRIC Results:"
grep -E "GB/s|error" "$LOG_DIR/libfabric-node1.log" | tail -5 || echo "Check logs"
echo ""

# Clean ETCD for next test
kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
sleep 2

# Option 2: Try UCX Native (skip nixlbench)
echo "═══════════════════════════════════════════════════════════════"
echo "TEST 2: UCX Native (No ETCD needed)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get node IPs
NODE1_IP=$(kubectl get pod nixl-bench-node1 -o jsonpath='{.status.podIP}')
echo "Node1 IP: $NODE1_IP"

echo "Starting UCX server on nixl-bench-node1..."
kubectl exec nixl-bench-node1 -- bash -c '
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 1073741824 -n 20 -w 10 -p 12345
' > "$LOG_DIR/ucx-server.log" 2>&1 &

SERVER_PID=$!
sleep 5

echo "Starting UCX client on nixl-bench-node2..."
kubectl exec nixl-bench-node2 -- bash -c "
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest $NODE1_IP -t ucp_put_bw -m cuda -s 1073741824 -n 20 -w 10 -p 12345
" 2>&1 | tee "$LOG_DIR/ucx-client.log"

kill $SERVER_PID 2>/dev/null || true

echo ""
echo "UCX Native Results:"
grep -E "Final:|1073741824" "$LOG_DIR/ucx-client.log" | tail -2
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Logs saved to: $LOG_DIR"
echo ""
echo "1. LIBFABRIC with DRAM: $(grep -E 'GB/s|Final' "$LOG_DIR/libfabric-node1.log" 2>/dev/null | tail -1)"
echo "2. UCX Native: $(grep -E 'Final:|GB/s' "$LOG_DIR/ucx-client.log" 2>/dev/null | tail -1)"
echo ""
echo "Recommendation: Use UCX Native for best performance (no ETCD issues)"
echo ""