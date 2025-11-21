#!/bin/bash
# NIXL Benchmark Test Commands for Two Pods
# Run these commands directly in your exec'd pods

echo "═══════════════════════════════════════════════════════════"
echo "         NIXL BENCHMARK TEST BETWEEN TWO PODS"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Prerequisites:"
echo "- You should be exec'd into both pods"
echo "- Pod 1 (Server): Will run the NIXL server"
echo "- Pod 2 (Client): Will run the NIXL client"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: On Pod 1 (SERVER) - Start NIXL Server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Basic NIXL server:"
cat << 'EOF'
cd /workspace/nixl
./nixl_benchmarks --server --port 5555
EOF
echo ""
echo "# Or with specific GPU and verbose output:"
cat << 'EOF'
cd /workspace/nixl
CUDA_VISIBLE_DEVICES=0 ./nixl_benchmarks --server --port 5555 --verbose
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: On Pod 2 (CLIENT) - Run NIXL Client"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Replace SERVER_IP with Pod 1's IP address"
echo "# If Pod 1 IP is 10.1.238.41, run:"
cat << 'EOF'
cd /workspace/nixl
./nixl_benchmarks --client --host 10.1.238.41 --port 5555
EOF
echo ""
echo "# Or with specific test parameters:"
cat << 'EOF'
cd /workspace/nixl
CUDA_VISIBLE_DEVICES=0 ./nixl_benchmarks --client --host 10.1.238.41 --port 5555 \
  --size 1073741824 \
  --iterations 10 \
  --warmup 5 \
  --verbose
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ALTERNATIVE: Run NIXL Python Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# On Pod 1 (SERVER):"
cat << 'EOF'
cd /workspace/nixl
python3 -c "
import nixl
import torch

# Initialize NIXL
nixl.init()

# Create a tensor
size = 1024 * 1024 * 256  # 1GB
tensor = torch.rand(size, device='cuda')

print('NIXL Server ready on', nixl.get_local_ip())
print('Waiting for client...')

# Run benchmark
nixl.benchmark_server(tensor, port=5555)
"
EOF
echo ""
echo "# On Pod 2 (CLIENT):"
cat << 'EOF'
cd /workspace/nixl
python3 -c "
import nixl
import torch

# Initialize NIXL
nixl.init()

# Connect to server
server_ip = '10.1.238.41'  # Replace with Pod 1's IP

# Create a tensor
size = 1024 * 1024 * 256  # 1GB
tensor = torch.zeros(size, device='cuda')

print(f'Connecting to NIXL server at {server_ip}:5555')

# Run benchmark
results = nixl.benchmark_client(tensor, host=server_ip, port=5555, iterations=10)
print(f'Bandwidth: {results["bandwidth_gbps"]:.2f} GB/s')
print(f'Latency: {results["latency_us"]:.2f} us')
"
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION 3: Run NIXL AllReduce Test (Multi-GPU)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# On BOTH pods simultaneously:"
cat << 'EOF'
cd /workspace/nixl

# Set up for multi-node AllReduce
export NIXL_RANK=0  # Set to 0 on first pod, 1 on second pod
export NIXL_WORLD_SIZE=2
export NIXL_MASTER_ADDR=10.1.238.41  # Pod 1's IP
export NIXL_MASTER_PORT=5555

# Run AllReduce benchmark
./nixl_allreduce_bench \
  --size 1073741824 \
  --iterations 100 \
  --warmup 10
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTION 4: Check NIXL Installation and Devices"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# First, verify NIXL is properly installed:"
cat << 'EOF'
cd /workspace/nixl

# Check NIXL binary
ls -la nixl_benchmarks

# Check for NIXL Python module
python3 -c "import nixl; print('NIXL version:', nixl.__version__ if hasattr(nixl, '__version__') else 'Unknown')"

# List available EFA devices
ls /dev/infiniband/

# Check NVIDIA GPUs
nvidia-smi --list-gpus

# Check EFA/libfabric info
fi_info -p efa
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "IMPORTANT NOTES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Start the SERVER first (Pod 1), then run CLIENT (Pod 2)"
echo "2. Make sure to use the correct IP addresses"
echo "3. The NIXL benchmark should utilize all 32 EFA devices automatically"
echo "4. Monitor your network dashboard to see NIC utilization"
echo "5. Expected bandwidth with 32 NICs: ~10-12 GB/s"
echo ""
echo "If nixl_benchmarks binary doesn't exist, try:"
echo "  - Look for other benchmark binaries: ls /workspace/nixl/*bench*"
echo "  - Use Python benchmarks instead"
echo "  - Check /opt/nixl or /usr/local/nixl directories"
echo ""