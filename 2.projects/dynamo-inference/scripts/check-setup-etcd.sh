#!/bin/bash
# Check and Setup ETCD for NIXLBENCH

echo "═══════════════════════════════════════════════════════════"
echo "           ETCD SERVER CHECK AND SETUP"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Check if ETCD is running"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Check for ETCD process:
ps aux | grep -i etcd | grep -v grep

# Check if ETCD is listening on port 2379:
netstat -tlnp | grep 2379

# Or using ss:
ss -tlnp | grep 2379

# Check if etcd binary exists:
which etcd

# Try to connect to ETCD (if running):
etcdctl endpoint health --endpoints=localhost:2379

# Or with curl:
curl -L http://localhost:2379/version
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Quick ETCD Setup (if not running)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Option A: Start ETCD in a container (easiest):"
cat << 'EOF'
# On Pod 1 (or any pod), run ETCD in background:
docker run -d \
  --name etcd \
  --network host \
  -e ALLOW_NONE_AUTHENTICATION=yes \
  -e ETCD_ADVERTISE_CLIENT_URLS=http://0.0.0.0:2379 \
  -e ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379 \
  quay.io/coreos/etcd:latest \
  /usr/local/bin/etcd

# Check if it's running:
docker ps | grep etcd

# Check logs:
docker logs etcd
EOF
echo ""

echo "Option B: Run ETCD directly (if installed):"
cat << 'EOF'
# Start ETCD in background:
nohup etcd \
  --name node1 \
  --listen-client-urls http://0.0.0.0:2379 \
  --advertise-client-urls http://10.1.238.41:2379 \
  --listen-peer-urls http://0.0.0.0:2380 \
  --data-dir /tmp/etcd-data \
  > /tmp/etcd.log 2>&1 &

# Check if it started:
tail -f /tmp/etcd.log
EOF
echo ""

echo "Option C: Install and run ETCD:"
cat << 'EOF'
# Download ETCD (if not installed):
ETCD_VER=v3.5.9
DOWNLOAD_URL=https://github.com/etcd-io/etcd/releases/download

# For Linux:
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd.tar.gz
tar xzf /tmp/etcd.tar.gz -C /tmp
sudo mv /tmp/etcd-${ETCD_VER}-linux-amd64/etcd* /usr/local/bin/

# Start ETCD:
/usr/local/bin/etcd \
  --listen-client-urls http://0.0.0.0:2379 \
  --advertise-client-urls http://0.0.0.0:2379 \
  > /tmp/etcd.log 2>&1 &
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Simple ETCD in background (quickest)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# If etcd binary exists, just run:
etcd > /tmp/etcd.log 2>&1 &

# Or with minimal config:
etcd --listen-client-urls=http://0.0.0.0:2379 \
     --advertise-client-urls=http://localhost:2379 \
     > /tmp/etcd.log 2>&1 &

# Check if it's working:
curl http://localhost:2379/version
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Run nixlbench with ETCD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# After ETCD is running on Pod 1 (10.1.238.41), run on BOTH pods:

nixlbench \
  -etcd_endpoints="10.1.238.41:2379" \
  -backend=UCX \
  -device_list=all \
  -scheme=pairwise \
  -target_seg_type=VRAM \
  -total_buffer_size=8589934592 \
  -start_block_size=1073741824 \
  -warmup_iter=10 \
  -benchmark_group=test1
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Kill ETCD after testing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat << 'EOF'
# Kill ETCD process:
pkill etcd

# Or if running in Docker:
docker stop etcd
docker rm etcd
EOF
echo ""