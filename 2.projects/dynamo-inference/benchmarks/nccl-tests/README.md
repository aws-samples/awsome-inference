# NCCL Collective Operations Benchmarks

This directory contains scripts for benchmarking NVIDIA Collective Communications Library (NCCL) performance on AWS instances with multiple GPUs.

## Overview

NCCL provides optimized collective communication primitives for multi-GPU and multi-node applications. These benchmarks test the performance of various NCCL operations on H100 GPUs with Elastic Fabric Adapter (EFA) for inter-node communication.

## Collective Operations

### All-Reduce
Reduces data across all GPUs and distributes the result to all GPUs. Common in distributed training for gradient aggregation.

**Expected Performance**: ~400 GB/s on 8x H100 GPUs

### All-Gather
Gathers data from all GPUs and distributes the concatenated result to all GPUs.

**Expected Performance**: ~350 GB/s on 8x H100 GPUs

### Reduce-Scatter
Reduces data and scatters unique portions to each GPU. Inverse of All-Gather.

**Expected Performance**: ~350 GB/s on 8x H100 GPUs

### Broadcast
Sends data from one GPU to all other GPUs.

### All-to-All
Each GPU sends unique data to every other GPU.

**Expected Performance**: ~300 GB/s on 8x H100 GPUs

## Prerequisites

### 1. Install NCCL Tests

```bash
# Clone the repository
git clone https://github.com/NVIDIA/nccl-tests.git
cd nccl-tests

# Build with MPI support
make MPI=1 MPI_HOME=/opt/amazon/openmpi

# Add to PATH
export PATH=$PATH:$(pwd)/build
```

### 2. Verify GPU Setup

```bash
# Check GPUs are visible
nvidia-smi

# Check GPU topology (should show NVLink connections)
nvidia-smi topo -m

# Verify all 8 GPUs are available
nvidia-smi --query-gpu=index,name --format=csv
```

### 3. Verify EFA (for multi-node)

```bash
# Check EFA devices
fi_info -p efa

# Test EFA bandwidth
efa_bandwidth

# Verify RDMA
fi_info -p efa -c FI_EP_RDM
```

## Scripts

### 1. run-nccl-tests.sh

Main script that runs all NCCL collective operation tests.

**Usage:**
```bash
./run-nccl-tests.sh
```

**Environment Variables:**
- `NUM_GPUS`: Number of GPUs to use (default: 8)
- `MIN_SIZE`: Minimum message size in bytes (default: 1MB)
- `MAX_SIZE`: Maximum message size in bytes (default: 8GB)
- `WARMUP_ITERS`: Number of warmup iterations (default: 5)
- `ITERS`: Number of test iterations (default: 20)
- `NCCL_DEBUG`: NCCL debug level (default: INFO)

**Example:**
```bash
# Run with custom configuration
NUM_GPUS=4 ITERS=50 ./run-nccl-tests.sh

# Run with debug output
NCCL_DEBUG=TRACE ./run-nccl-tests.sh

# Test with larger messages
MAX_SIZE=$((16*1024*1024*1024)) ./run-nccl-tests.sh
```

### 2. nccl-allreduce.sh

Focused testing for all-reduce operations with detailed profiling.

**Usage:**
```bash
./nccl-allreduce.sh
```

**Features:**
- Detailed performance analysis
- Efficiency calculations vs expected performance
- Debug log collection
- Troubleshooting recommendations

**Example:**
```bash
# Run with more iterations for stable results
ITERS=100 WARMUP_ITERS=20 ./nccl-allreduce.sh

# Test specific message size range
MIN_SIZE=$((128*1024*1024)) MAX_SIZE=$((2*1024*1024*1024)) ./nccl-allreduce.sh
```

### 3. nccl-bandwidth.sh

Comprehensive bandwidth testing across various message sizes.

**Usage:**
```bash
./nccl-bandwidth.sh
```

**Test Categories:**
- Small messages: 1KB - 1MB
- Medium messages: 1MB - 128MB
- Large messages: 128MB - 2GB
- Very large messages: 2GB - 8GB
- All collectives at optimal size: 128MB - 1GB

**Features:**
- Tests multiple message size ranges
- Compares all collective operations
- Generates CSV summary
- Performance validation

**Example:**
```bash
# Run bandwidth tests with custom GPU count
NUM_GPUS=4 ./nccl-bandwidth.sh

# More iterations for accuracy
ITERS=50 WARMUP_ITERS=10 ./nccl-bandwidth.sh
```

## NCCL Environment Variables

### Core Settings

```bash
# Debug output
export NCCL_DEBUG=INFO                    # Options: VERSION, WARN, INFO, TRACE
export NCCL_DEBUG_SUBSYS=INIT,COLL       # Subsystems to debug

# Network configuration
export NCCL_IB_DISABLE=0                  # Enable InfiniBand/EFA (0=enabled)
export NCCL_SOCKET_IFNAME=ens             # Network interface prefix
```

### EFA Optimizations

```bash
# EFA provider configuration
export FI_PROVIDER=efa                    # Use EFA as the libfabric provider
export FI_EFA_USE_DEVICE_RDMA=1          # Enable RDMA on EFA
export FI_EFA_FORK_SAFE=1                # Enable fork safety

# NCCL EFA optimizations
export NCCL_TREE_THRESHOLD=4294967296    # Use ring algorithm for large messages
export NCCL_PROTO=Simple                  # Use simple protocol (optimal for EFA)
```

### Performance Tuning

```bash
# Buffer and communication settings
export NCCL_BUFFSIZE=2097152             # 2MB buffer size
export NCCL_P2P_DISABLE=0                # Enable peer-to-peer (0=enabled)
export NCCL_SHM_DISABLE=0                # Enable shared memory (0=enabled)
export NCCL_NET_GDR_LEVEL=5              # GPUDirect RDMA level
export NCCL_CROSS_NIC=1                  # Enable cross-NIC communication
```

### Multi-Node Settings

```bash
# For distributed training across nodes
export NCCL_MIN_NRINGS=8                 # Minimum number of rings
export NCCL_MAX_NRINGS=16                # Maximum number of rings
export NCCL_NTHREADS=256                 # Number of NCCL threads
```

## Expected Performance

### Single Node (8x H100 GPUs with NVLink)

| Operation | Bandwidth | Latency (1GB) |
|-----------|-----------|---------------|
| All-Reduce | ~400 GB/s | ~2-3 ms |
| All-Gather | ~350 GB/s | ~2-3 ms |
| Reduce-Scatter | ~350 GB/s | ~2-3 ms |
| Broadcast | ~300 GB/s | ~2-3 ms |
| All-to-All | ~300 GB/s | ~3-4 ms |

### Multi-Node (with EFA)

Performance depends on EFA bandwidth (typically 100-400 Gbps per node):

| Operation | Bandwidth | Notes |
|-----------|-----------|-------|
| All-Reduce | ~100-200 GB/s | Limited by inter-node bandwidth |
| All-Gather | ~80-150 GB/s | Network bound |
| Reduce-Scatter | ~80-150 GB/s | Network bound |

## Interpreting Results

### Sample Output

```
#       size         count      type   redop    root     time   algbw   busbw
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)
   134217728      33554432     float     sum      -1   2342.1  57.30  106.94
   268435456      67108864     float     sum      -1   4523.2  59.34  110.76
   536870912     134217728     float     sum      -1   8934.5  60.12  112.22
  1073741824     268435456     float     sum      -1  17234.8  62.31  116.33
```

**Columns:**
- `size`: Message size in bytes
- `count`: Number of elements
- `type`: Data type
- `time`: Time in microseconds
- `algbw`: Algorithm bandwidth (GB/s) - raw data transferred
- `busbw`: Bus bandwidth (GB/s) - effective bandwidth considering NCCL overhead

### Performance Validation

```bash
# Check if performance meets expectations
if [ $MEASURED_BW -ge 350 ]; then
    echo "✓ Excellent performance"
elif [ $MEASURED_BW -ge 300 ]; then
    echo "⚠ Good performance, but room for improvement"
else
    echo "✗ Poor performance, troubleshooting needed"
fi
```

## Troubleshooting

### Low Bandwidth (<350 GB/s on 8x H100)

**Check GPU Topology:**
```bash
nvidia-smi topo -m
# Should show NVSwitch or NVLink connections between GPUs
```

**Verify GPU Clocks:**
```bash
nvidia-smi -q | grep -A 5 Clocks
# Ensure GPUs are not throttled
```

**Check EFA (multi-node):**
```bash
# Verify EFA devices
fi_info -p efa

# Check EFA bandwidth
efa_bandwidth

# Verify RDMA capability
ibv_devinfo
```

**Review NCCL Logs:**
```bash
NCCL_DEBUG=INFO ./run-nccl-tests.sh 2>&1 | grep -E "Using|Ring|Tree"
```

### NCCL Connection Failures

**Check Network Interface:**
```bash
# List network interfaces
ip link show

# Ensure the correct interface is used
export NCCL_SOCKET_IFNAME=ens
```

**Verify Firewall Rules:**
```bash
# Check if ports are open (NCCL typically uses random ports)
sudo iptables -L

# For multi-node, ensure security groups allow traffic
```

### Memory Issues

**Reduce Message Size:**
```bash
MAX_SIZE=$((4*1024*1024*1024)) ./run-nccl-tests.sh
```

**Check GPU Memory:**
```bash
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

## Multi-Node Testing

### Using MPI

```bash
# Create hostfile with node IPs
cat > hostfile <<EOF
node1-ip slots=8
node2-ip slots=8
EOF

# Run across nodes
mpirun -np 16 \
    --hostfile hostfile \
    --mca btl tcp,self \
    --mca btl_tcp_if_include ens \
    --bind-to none \
    -x NCCL_DEBUG=INFO \
    -x FI_PROVIDER=efa \
    -x FI_EFA_USE_DEVICE_RDMA=1 \
    -x NCCL_TREE_THRESHOLD=4294967296 \
    all_reduce_perf -b 1M -e 8G -f 2 -g 1
```

### Using PyTorch Distributed

```python
import torch
import torch.distributed as dist

# Initialize process group with NCCL backend
dist.init_process_group(
    backend='nccl',
    init_method='env://',
)

# Test all-reduce
tensor = torch.randn(1000000).cuda()
dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
```

## Best Practices

1. **Always run warmup iterations** to allow NCCL to optimize communication patterns
2. **Use appropriate message sizes** - NCCL performs best with large messages (>128MB)
3. **Enable EFA for multi-node** - Ensure `FI_PROVIDER=efa` is set
4. **Monitor GPU clocks** - Ensure GPUs are not throttled during tests
5. **Test incrementally** - Start with single-node, then expand to multi-node
6. **Compare against baselines** - Keep historical results for regression testing
7. **Use NCCL_DEBUG=INFO** - Always check logs for warnings or errors

## References

- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/index.html)
- [NCCL Tests Repository](https://github.com/NVIDIA/nccl-tests)
- [AWS EFA Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html)
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)

## Support

For issues or questions:
1. Check NCCL debug logs with `NCCL_DEBUG=INFO`
2. Verify GPU topology and EFA configuration
3. Review AWS EFA documentation for network setup
4. Consult NVIDIA NCCL documentation for tuning parameters
