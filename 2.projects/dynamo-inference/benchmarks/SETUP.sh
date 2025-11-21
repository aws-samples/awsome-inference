#!/bin/bash
# One-command setup for the entire benchmark suite

set -e

BENCHMARK_DIR="/home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks"

echo "═══════════════════════════════════════════════════════════════"
echo "     DYNAMO BENCHMARK SUITE - COMPLETE SETUP"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "This will create:"
echo "  1. UCX native benchmark (285 GB/s per NIC)"
echo "  2. NIXL LIBFABRIC benchmark (46.48 GB/s proven)"
echo "  3. NIXL UCX benchmark (0.85 GB/s, comparison only)"
echo "  4. NCCL collective operations tests (400 GB/s expected)"
echo "  5. Cluster deployment scripts"
echo ""

# Ensure benchmark directory exists
mkdir -p "$BENCHMARK_DIR"
cd "$BENCHMARK_DIR"

# Check if folders already exist
if [ -d "ucx-benchmark" ] || [ -d "nixlbench-libfabric" ] || [ -d "nixlbench-ucx" ] || [ -d "nccl-tests" ]; then
    echo "⚠️  Some benchmark folders already exist."
    read -p "Do you want to continue and potentially overwrite? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 1
    fi
fi

# Run the setup script if it exists
if [ -f "setup-benchmark-suite.sh" ]; then
    echo "Running existing setup script..."
    chmod +x setup-benchmark-suite.sh
    ./setup-benchmark-suite.sh
else
    echo "Setup script not found. Please ensure all scripts have been created."
    exit 1
fi

# Make all scripts executable
find . -name "*.sh" -type f -exec chmod +x {} \;

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ SETUP COMPLETE!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Directory structure:"
echo "  $BENCHMARK_DIR/"
echo "  ├── ucx-benchmark/          # UCX native tests"
echo "  ├── nixlbench-libfabric/    # NIXL with LIBFABRIC (recommended)"
echo "  ├── nixlbench-ucx/          # NIXL with UCX (comparison)"
echo "  ├── nccl-tests/             # NCCL collective operations"
echo "  └── deploy-and-run-all.sh   # Master orchestration script"
echo ""
echo "Quick Start:"
echo "  cd $BENCHMARK_DIR"
echo "  ./deploy-and-run-all.sh     # Interactive menu to run benchmarks"
echo ""
echo "Or run individual benchmarks:"
echo "  cd ucx-benchmark && ./run-ucx-test.sh"
echo "  cd nixlbench-libfabric && ./run-libfabric-test.sh"
echo "  cd nixlbench-ucx && ./run-ucx-backend-test.sh"
echo "  cd nccl-tests && ./run-nccl-tests.sh"
echo ""
echo "Expected Performance:"
echo "  • UCX Native: 285 GB/s per NIC (up to 9 TB/s with 32 NICs)"
echo "  • NIXL LIBFABRIC: 46.48 GB/s (proven, recommended)"
echo "  • NIXL UCX: 0.85 GB/s (not recommended)"
echo "  • NCCL AllReduce: 400 GB/s (8x H100 GPUs)"
echo ""