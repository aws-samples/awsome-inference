#!/bin/bash
# Full Dynamo Cluster Deployment with Comprehensive Benchmark Suite
# Includes: UCX perftest, nixlbench with UCX backend, nixlbench with LIBFABRIC backend

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "     DYNAMO CLUSTER DEPLOYMENT & BENCHMARK SUITE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "This script will:"
echo "1. Clean up existing nixl-benchmark pods"
echo "2. Deploy full Dynamo cluster (frontend + backend)"
echo "3. Deploy disaggregated compute pods"
echo "4. Run UCX perftest benchmark"
echo "5. Run nixlbench with UCX backend"
echo "6. Run nixlbench with LIBFABRIC backend"
echo "7. Compare results"
echo ""

# Configuration
NAMESPACE="${NAMESPACE:-default}"
DYNAMO_NAMESPACE="${DYNAMO_NAMESPACE:-dynamo-cloud}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="/home/ubuntu/benchmark-results-$TIMESTAMP"

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "Results will be saved to: $RESULTS_DIR"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Clean up existing benchmark pods"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clean up old benchmark pods
echo "Removing existing nixl-benchmark pods..."
kubectl delete deployment nixl-benchmark --ignore-not-found=true
kubectl delete pod -l app=nixl-benchmark --ignore-not-found=true
kubectl delete pod nixl-benchmark-84d8b89c5b-7csx9 nixl-benchmark-84d8b89c5b-rbfnp --ignore-not-found=true

# Wait for cleanup
sleep 5

echo "✓ Cleanup complete"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Deploy Dynamo Cluster"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat << 'EOF' > "$RESULTS_DIR/dynamo-cluster.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: dynamo-cloud
---
# Frontend Pod
apiVersion: v1
kind: Pod
metadata:
  name: dynamo-frontend
  namespace: dynamo-cloud
  labels:
    app: dynamo
    tier: frontend
spec:
  containers:
  - name: dynamo-frontend
    image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:all-arch
    imagePullPolicy: IfNotPresent
    command: ["sleep", "infinity"]
    env:
    - name: DYNAMO_MODE
      value: "frontend"
    resources:
      requests:
        memory: "16Gi"
        cpu: "4"
      limits:
        memory: "32Gi"
        cpu: "8"
---
# Backend Pod 1 (with GPU and EFA)
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
    - name: DYNAMO_MODE
      value: "backend"
    - name: NODE_ID
      value: "1"
    - name: LD_LIBRARY_PATH
      value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/opt/amazon/efa/lib64"
    resources:
      requests:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
        memory: "32Gi"
        cpu: "8"
      limits:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
        memory: "64Gi"
        cpu: "16"
    securityContext:
      capabilities:
        add:
        - IPC_LOCK
        - SYS_RESOURCE
      privileged: true
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: tier
            operator: In
            values:
            - backend
        topologyKey: kubernetes.io/hostname
---
# Backend Pod 2 (with GPU and EFA)
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
    - name: DYNAMO_MODE
      value: "backend"
    - name: NODE_ID
      value: "2"
    - name: LD_LIBRARY_PATH
      value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/opt/amazon/efa/lib64"
    resources:
      requests:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
        memory: "32Gi"
        cpu: "8"
      limits:
        nvidia.com/gpu: 1
        vpc.amazonaws.com/efa: 1
        memory: "64Gi"
        cpu: "16"
    securityContext:
      capabilities:
        add:
        - IPC_LOCK
        - SYS_RESOURCE
      privileged: true
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: tier
            operator: In
            values:
            - backend
        topologyKey: kubernetes.io/hostname
EOF

echo "Deploying Dynamo cluster..."
kubectl apply -f "$RESULTS_DIR/dynamo-cluster.yaml"

# Wait for pods to be ready
echo "Waiting for Dynamo pods to be ready..."
kubectl wait --for=condition=Ready pod/dynamo-frontend -n dynamo-cloud --timeout=300s || true
kubectl wait --for=condition=Ready pod/dynamo-backend-1 -n dynamo-cloud --timeout=300s || true
kubectl wait --for=condition=Ready pod/dynamo-backend-2 -n dynamo-cloud --timeout=300s || true

echo "✓ Dynamo cluster deployed"
echo ""

# Get pod IPs
BACKEND1_IP=$(kubectl get pod dynamo-backend-1 -n dynamo-cloud -o jsonpath='{.status.podIP}')
BACKEND2_IP=$(kubectl get pod dynamo-backend-2 -n dynamo-cloud -o jsonpath='{.status.podIP}')
ETCD_IP=$(kubectl get pod dynamo-platform-etcd-0 -n dynamo-cloud -o jsonpath='{.status.podIP}' 2>/dev/null || echo "10.1.25.101")

echo "Backend Pod 1 IP: $BACKEND1_IP"
echo "Backend Pod 2 IP: $BACKEND2_IP"
echo "ETCD IP: $ETCD_IP"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Run Benchmark Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create benchmark scripts
cat << 'EOF' > "$RESULTS_DIR/run-ucx-benchmark.sh"
#!/bin/bash
# UCX Perftest Benchmark

echo "=== UCX Perftest Benchmark ==="
echo "Server: dynamo-backend-1"
echo "Client: dynamo-backend-2"
echo ""

# Start server on backend-1
kubectl exec dynamo-backend-1 -n dynamo-cloud -- bash -c '
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 100 -w 20 -p 12345
' > /tmp/ucx-server.log 2>&1 &

SERVER_PID=$!
sleep 5

# Run client on backend-2
kubectl exec dynamo-backend-2 -n dynamo-cloud -- bash -c "
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest BACKEND1_IP -t ucp_put_bw -m cuda -s 8589934592 -n 100 -w 20 -p 12345
" | tee /tmp/ucx-client.log

# Extract results
echo ""
echo "UCX Results:"
grep "Final:" /tmp/ucx-client.log || grep "8589934592" /tmp/ucx-client.log | tail -1
EOF

cat << 'EOF' > "$RESULTS_DIR/run-nixlbench-ucx.sh"
#!/bin/bash
# Nixlbench with UCX Backend

echo "=== Nixlbench with UCX Backend ==="
echo "Note: This may fail with 'target uri is not valid' error"
echo ""

# Clean ETCD
kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
sleep 2

BENCHMARK_GROUP="ucx-$(date +%s)"

# Start both pods simultaneously
kubectl exec dynamo-backend-1 -n dynamo-cloud -- bash -c "
nixlbench \
  --etcd_endpoints http://ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend UCX \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --warmup_iter 5
" > /tmp/nixl-ucx-1.log 2>&1 &

kubectl exec dynamo-backend-2 -n dynamo-cloud -- bash -c "
nixlbench \
  --etcd_endpoints http://ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend UCX \
  --target_seg_type DRAM \
  --total_buffer_size 1073741824 \
  --warmup_iter 5
" > /tmp/nixl-ucx-2.log 2>&1 &

wait

echo "Nixlbench UCX Results:"
grep -E "GB/s|Final" /tmp/nixl-ucx-*.log || echo "Failed (check logs)"
EOF

cat << 'EOF' > "$RESULTS_DIR/run-nixlbench-libfabric.sh"
#!/bin/bash
# Nixlbench with LIBFABRIC Backend

echo "=== Nixlbench with LIBFABRIC Backend ==="
echo "Expected: ~46 GB/s based on previous tests"
echo ""

# Clean ETCD
kubectl exec dynamo-platform-etcd-0 -n dynamo-cloud -- etcdctl del "" --prefix 2>/dev/null || true
sleep 2

BENCHMARK_GROUP="libfab-$(date +%s)"

# Start backend-2 first (becomes rank 0)
kubectl exec dynamo-backend-2 -n dynamo-cloud -- bash -c "
nixlbench \
  --etcd_endpoints http://ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend LIBFABRIC \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5
" > /tmp/nixl-libfab-2.log 2>&1 &

# Wait for registration
sleep 10

# Start backend-1 (becomes rank 1)
kubectl exec dynamo-backend-1 -n dynamo-cloud -- bash -c "
nixlbench \
  --etcd_endpoints http://ETCD_IP:2379 \
  --benchmark_group $BENCHMARK_GROUP \
  --backend LIBFABRIC \
  --worker_type nixl \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --op_type WRITE \
  --num_iter 50 \
  --warmup_iter 5
" | tee /tmp/nixl-libfab-1.log

echo ""
echo "Nixlbench LIBFABRIC Results:"
grep -E "GB/s|67108864" /tmp/nixl-libfab-1.log | tail -5
EOF

# Make scripts executable
chmod +x "$RESULTS_DIR"/*.sh

# Replace IPs in scripts
sed -i "s/BACKEND1_IP/$BACKEND1_IP/g" "$RESULTS_DIR/run-ucx-benchmark.sh"
sed -i "s/ETCD_IP/$ETCD_IP/g" "$RESULTS_DIR/run-nixlbench-ucx.sh"
sed -i "s/ETCD_IP/$ETCD_IP/g" "$RESULTS_DIR/run-nixlbench-libfabric.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Running Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Run UCX benchmark
echo ""
echo "Running UCX Perftest..."
bash "$RESULTS_DIR/run-ucx-benchmark.sh" | tee "$RESULTS_DIR/ucx-results.txt"

# Run nixlbench with UCX
echo ""
echo "Running nixlbench with UCX backend..."
bash "$RESULTS_DIR/run-nixlbench-ucx.sh" | tee "$RESULTS_DIR/nixlbench-ucx-results.txt"

# Run nixlbench with LIBFABRIC
echo ""
echo "Running nixlbench with LIBFABRIC backend..."
bash "$RESULTS_DIR/run-nixlbench-libfabric.sh" | tee "$RESULTS_DIR/nixlbench-libfabric-results.txt"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Results Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat << EOF > "$RESULTS_DIR/benchmark-summary.md"
# Benchmark Results Summary
Date: $(date)

## Test Configuration
- Cluster: Dynamo disaggregated deployment
- Backend 1 IP: $BACKEND1_IP
- Backend 2 IP: $BACKEND2_IP
- ETCD IP: $ETCD_IP
- Instance Type: $(kubectl get nodes -o jsonpath='{.items[0].metadata.labels.node\.kubernetes\.io/instance-type}')

## Results

### 1. UCX Perftest (Native)
$(grep -E "Final:|GB/s" "$RESULTS_DIR/ucx-results.txt" | tail -3)

### 2. Nixlbench with UCX Backend
$(grep -E "GB/s|Final|error" "$RESULTS_DIR/nixlbench-ucx-results.txt" | tail -3)

### 3. Nixlbench with LIBFABRIC Backend
$(grep -E "GB/s|67108864" "$RESULTS_DIR/nixlbench-libfabric-results.txt" | tail -3)

## Expected Performance
- UCX Perftest: ~300 MB/s to 10+ GB/s (depending on NIC utilization)
- Nixlbench UCX: May fail with "target uri is not valid" error
- Nixlbench LIBFABRIC: ~46 GB/s (based on previous tests)

## Logs Location
All logs saved to: $RESULTS_DIR
EOF

echo ""
cat "$RESULTS_DIR/benchmark-summary.md"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "To view pods:"
echo "  kubectl get pods -n dynamo-cloud"
echo ""
echo "To exec into backend pods:"
echo "  kubectl exec -it dynamo-backend-1 -n dynamo-cloud -- bash"
echo "  kubectl exec -it dynamo-backend-2 -n dynamo-cloud -- bash"
echo ""
echo "To cleanup:"
echo "  kubectl delete -f $RESULTS_DIR/dynamo-cluster.yaml"
echo ""