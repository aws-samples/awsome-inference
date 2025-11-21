#!/bin/bash
# Clean ETCD and retry nixlbench with known working patterns

echo "═══════════════════════════════════════════════════════════"
echo "       NIXLBENCH WITH ETCD CLEANUP AND RETRY"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Get ETCD service endpoint"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Get ETCD service ClusterIP:"
cat << 'EOF'
kubectl get svc -A | grep etcd

# If you see etcd-service, get its IP:
ETCD_IP=$(kubectl get svc etcd-service -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo "ETCD Service IP: $ETCD_IP"

# Or get the pod IP directly:
ETCD_POD_IP=$(kubectl get pod etcd-0 -o jsonpath='{.status.podIP}')
echo "ETCD Pod IP: $ETCD_POD_IP"
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Clean ETCD state (CRITICAL!)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# From outside the pods, clean ETCD:"
cat << 'EOF'
kubectl exec etcd-0 -- etcdctl del "" --prefix

# Or if etcdctl needs API version:
kubectl exec etcd-0 -- sh -c 'ETCDCTL_API=3 etcdctl del "" --prefix'

# Verify it's empty:
kubectl exec etcd-0 -- sh -c 'ETCDCTL_API=3 etcdctl get "" --prefix'
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Try the LIBFABRIC backend (worked before)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Based on successful Nov 18 test that achieved 45.94 GB/s:"
echo ""
echo "# Generate unique benchmark group:"
echo 'BENCHMARK_GROUP="libfab-test-$(date +%s)"'
echo ""
echo "# On Pod 2 FIRST (becomes rank 0 - target):"
cat << 'EOF'
# Get ETCD endpoint (use pod IP or service IP)
ETCD_ENDPOINT="http://etcd-0:2379"  # or use the IP you found

nixlbench \
  --etcd_endpoints ${ETCD_ENDPOINT} \
  --benchmark_group ${BENCHMARK_GROUP} \
  --backend LIBFABRIC \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5
EOF
echo ""
echo "# Wait 10 seconds for Pod 2 to register..."
echo ""
echo "# Then on Pod 1 (becomes rank 1 - initiator):"
cat << 'EOF'
# Same command
ETCD_ENDPOINT="http://etcd-0:2379"  # or use the IP you found

nixlbench \
  --etcd_endpoints ${ETCD_ENDPOINT} \
  --benchmark_group ${BENCHMARK_GROUP} \
  --backend LIBFABRIC \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Alternative - Try with explicit device"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Sometimes specifying device helps:"
cat << 'EOF'
nixlbench \
  --etcd_endpoints http://etcd-0:2379 \
  --benchmark_group test-explicit \
  --backend UCX \
  --device_list rdmap113s0:1 \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --start_block_size 134217728 \
  --warmup_iter 5
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: If nixlbench still fails - Use proven UCX"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "UCX perftest is PROVEN to work (307 MB/s achieved):"
echo ""
echo "# On Pod 1 (server):"
cat << 'EOF'
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_RNDV_SCHEME=put_rail
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p 12345
EOF
echo ""
echo "# On Pod 2 (client):"
cat << 'EOF'
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_RNDV_SCHEME=put_rail
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p 12345
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DEBUGGING TIPS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Check ETCD connectivity from pod:"
echo "   curl http://etcd-0:2379/version"
echo ""
echo "2. Monitor what's being written to ETCD:"
echo "   kubectl exec etcd-0 -- sh -c 'ETCDCTL_API=3 etcdctl watch ""  --prefix'"
echo ""
echo "3. Check if pods can resolve etcd-0:"
echo "   nslookup etcd-0"
echo "   ping etcd-0"
echo ""
echo "4. If using hostNetwork, may need to use IP instead of hostname"
echo ""