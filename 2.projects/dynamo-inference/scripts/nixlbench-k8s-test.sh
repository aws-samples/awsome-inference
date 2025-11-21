#!/bin/bash
# NIXLBENCH Test Script for Kubernetes Pods
# Based on successful tests from November 2024

echo "═══════════════════════════════════════════════════════════"
echo "    NIXLBENCH KUBERNETES TEST - BASED ON WORKING CONFIG"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Generate unique benchmark group to prevent conflicts
BENCHMARK_GROUP="nixl-test-$(date +%s)"
echo "Benchmark Group: $BENCHMARK_GROUP"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Check if ETCD is available in your cluster"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Check for ETCD service:"
echo "kubectl get svc | grep etcd"
echo ""
echo "# Check for ETCD pods:"
echo "kubectl get pods --all-namespaces | grep etcd"
echo ""
echo "# If ETCD service exists, get its ClusterIP:"
echo "kubectl get svc etcd-service -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo 'No etcd-service found'"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION A: If NO ETCD exists - Start one on Pod 1"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# On Pod 1, start ETCD in background:"
cat << 'EOF'
# Check if etcd binary exists:
which etcd

# If etcd exists, start it:
etcd --listen-client-urls=http://0.0.0.0:2379 \
     --advertise-client-urls=http://0.0.0.0:2379 \
     --data-dir=/tmp/etcd-data \
     > /tmp/etcd.log 2>&1 &

# Verify it's running:
sleep 3
curl http://localhost:2379/version

# Get Pod 1's IP for Pod 2 to connect:
hostname -i
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION B: If ETCD service exists - Use it directly"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# The documentation shows ETCD service at: 172.20.32.220:2379"
echo "# But verify your actual ETCD service IP first"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Run nixlbench - CRITICAL TIMING!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Based on the documentation, the order matters!"
echo ""
echo "# 1. FIRST start on Pod 2 (will become rank 0 - target):"
cat << 'EOF'
# Replace ETCD_IP with actual ETCD endpoint (Pod1 IP or service IP)
ETCD_IP="10.1.238.41"  # or "172.20.32.220" if using service

nixlbench \
  --etcd_endpoints http://${ETCD_IP}:2379 \
  --benchmark_group nixl-test-123456 \
  --backend UCX \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5 \
  --total_buffer_size 8589934592 \
  --start_block_size 1073741824
EOF
echo ""
echo "# 2. Wait 5-10 seconds for Pod 2 to register"
echo ""
echo "# 3. THEN start on Pod 1 (will become rank 1 - initiator):"
cat << 'EOF'
# Same command as Pod 2
ETCD_IP="10.1.238.41"  # or "172.20.32.220" if using service

nixlbench \
  --etcd_endpoints http://${ETCD_IP}:2379 \
  --benchmark_group nixl-test-123456 \
  --backend UCX \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5 \
  --total_buffer_size 8589934592 \
  --start_block_size 1073741824
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Alternative: Simple test with smaller buffer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Quick test with 1GB buffer - run on BOTH pods:
# Pod 2 first, then Pod 1 after 5-10 seconds

nixlbench \
  --etcd_endpoints http://10.1.238.41:2379 \
  --benchmark_group quick-test \
  --backend UCX \
  --target_seg_type VRAM \
  --total_buffer_size 1073741824 \
  --start_block_size 134217728 \
  --warmup_iter 5
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "IMPORTANT NOTES from documentation:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. ORDER MATTERS: Start Pod 2 FIRST, wait, then Pod 1"
echo "2. Pod 2 becomes rank 0 (target)"
echo "3. Pod 1 becomes rank 1 (initiator)"
echo "4. Both must use same --benchmark_group value"
echo "5. If you see 'both pods register as rank 0' - timing is wrong"
echo "6. Clean ETCD between tests if needed:"
echo "   etcdctl del '' --prefix"
echo ""
echo "Previous successful test achieved 45.94 GB/s with LIBFABRIC backend"
echo "UCX backend achieved 284.98 GB/s in direct UCX tests"
echo ""
echo "Monitor your network dashboard to see which NICs activate!"
echo ""