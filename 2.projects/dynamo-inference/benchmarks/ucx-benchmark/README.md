# UCX Benchmark - Native UCX Performance Testing

This folder contains scripts and documentation for benchmarking native UCX performance on AWS EFA with GPU Direct RDMA.

## Overview

UCX (Unified Communication X) is a high-performance communication framework that provides efficient point-to-point and collective communication for parallel computing. On AWS EFA (Elastic Fabric Adapter), UCX uses the SRD (Scalable Reliable Datagram) transport for maximum performance.

## Expected Performance

Based on working configurations and AWS specifications:

- **Single NIC Baseline**: ~307 MB/s (proven)
- **Single NIC Maximum**: 285 GB/s per NIC (theoretical)
- **Multi-NIC (32 rails)**: ~9 TB/s total (32 x 285 GB/s)

**Note**: The 285 GB/s per NIC is based on the theoretical maximum of EFA devices. Actual performance will vary based on:
- Buffer sizes (larger buffers achieve higher throughput)
- GPU memory bandwidth
- Network topology and congestion
- UCX configuration parameters

## Test Configuration

### Transport Layer
- **Primary Transport**: SRD (Scalable Reliable Datagram) - native EFA protocol
- **GPU Transports**: cuda_copy, cuda_ipc - for GPU memory handling
- **GPU Direct RDMA**: gdr_copy - for direct GPU-to-network transfers (when available)

### Multi-Rail Configuration
Multi-rail allows UCX to stripe data across multiple network devices simultaneously:

- **UCX_MAX_RNDV_RAILS=32**: Use up to 32 rails for rendezvous protocol (large messages)
- **UCX_MAX_EAGER_RAILS=32**: Use up to 32 rails for eager protocol (small messages)
- **UCX_NET_DEVICES=all**: Detect and use all available EFA devices
- **UCX_IB_NUM_PATHS=32**: Enable 32 parallel paths (may not apply to SRD but worth testing)

### SRD-Specific Optimizations
- **UCX_SRD_TX_QUEUE_LEN=8192**: Increase transmit queue length
- **UCX_SRD_RX_QUEUE_LEN=8192**: Increase receive queue length
- **UCX_SRD_MAX_NUM_EPS=256**: Support more concurrent endpoints
- **UCX_SRD_SEG_SIZE=16384**: Optimize segment size for large transfers

### Rail Striping
- **UCX_RNDV_SCHEME=put_rail**: Use rail-based PUT scheme for optimal distribution
- **UCX_RNDV_THRESH=1024**: Lower threshold to use rails sooner (bytes)
- **UCX_ZCOPY_THRESH=32768**: Zero-copy threshold for direct memory access

## Prerequisites

1. **Kubernetes Cluster**: With GPU nodes and EFA support
2. **EFA Device Plugin**: Running on all GPU nodes
3. **UCX Installation**: ucx_perftest binary available in container
4. **GPU Support**: CUDA-enabled GPUs with EFA adapter
5. **Two Pods**: Deployed on different nodes for network testing

## File Structure

```
ucx-benchmark/
├── README.md               # This file
├── run-ucx-test.sh        # Main test script with all configurations
└── results/               # Directory for test results
    └── ucx-test-*.log     # Timestamped test results
```

## Running the Tests

### Step 1: Deploy Test Pods

You need two pods running on different nodes with:
- CUDA-enabled GPU access
- EFA device access
- UCX tools installed

Example pod specification requirements:
```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    vpc.amazonaws.com/efa: 1
```

### Step 2: Find Server Pod IP

On the server pod, get its IP address:
```bash
hostname -i
```

Update the `SERVER_IP` variable in `run-ucx-test.sh` with this IP address.

### Step 3: Run the Test Script

On the client pod, run:
```bash
cd /home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks/ucx-benchmark
./run-ucx-test.sh
```

The script will guide you through each test, providing:
- Environment variables to set on both server and client
- Commands to run on server pod (start first)
- Commands to run on client pod (start after server is ready)
- Prompts to record results before moving to the next test

### Step 4: Running Individual Tests

Each test requires:

1. **On SERVER pod** - Start the server first:
```bash
# Set environment variables (from script output)
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32

# Start server
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -p <PORT>
```

2. **On CLIENT pod** - Start after server is ready:
```bash
# Set the same environment variables
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32

# Start client test
CUDA_VISIBLE_DEVICES=0 ucx_perftest <SERVER_IP> -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p <PORT>
```

## Test Descriptions

### Test 1: Single NIC Baseline
- **Purpose**: Establish baseline with proven working configuration
- **Configuration**: Single EFA device (rdmap113s0:1)
- **Buffer**: 1GB
- **Expected**: ~307 MB/s (proven result)
- **Significance**: Validates that basic UCX setup is working

### Test 2: Multi-NIC with 32 Rails (1GB buffer)
- **Purpose**: Test multi-rail capability with moderate buffer size
- **Configuration**: All devices, 32 rails enabled
- **Buffer**: 1GB
- **Expected**: ~9-10 GB/s
- **Significance**: Shows multi-rail scaling before hitting GPU memory bandwidth limits

### Test 3: Multi-NIC with GDR Copy (8GB buffer)
- **Purpose**: Maximum performance test with GPU Direct RDMA
- **Configuration**: All devices, 32 rails, GDR copy enabled
- **Buffer**: 8GB (maximum throughput size)
- **Expected**: Up to 285 GB/s per active NIC
- **Significance**: Tests peak network performance capability

### Test 4: Multi-NIC with SRD Optimizations (8GB buffer)
- **Purpose**: Test SRD-specific queue and endpoint optimizations
- **Configuration**: All devices, 32 rails, SRD queue tuning
- **Buffer**: 8GB
- **Expected**: Up to 285 GB/s per active NIC
- **Significance**: Validates SRD-specific performance tuning

### Test 5: Multi-NIC with Rail Striping (8GB buffer)
- **Purpose**: Test explicit rail striping scheme
- **Configuration**: put_rail scheme, lower thresholds
- **Buffer**: 8GB
- **Expected**: Up to 285 GB/s per active NIC
- **Significance**: Tests optimal data distribution across rails

## Understanding the Results

### Key Metrics

The ucx_perftest output will show:
```
------------------------------------------------------------------------------------------
| Buffer Size | Iterations | Bandwidth (MB/s) | Message Rate (msg/s) | Latency (us) |
------------------------------------------------------------------------------------------
| 8GB         | 50         | XXXXX.XX         | X.XX                 | XXXXX.XX     |
------------------------------------------------------------------------------------------
```

### Performance Analysis

1. **Bandwidth (MB/s)**: Main metric for throughput
   - Single NIC: ~307 MB/s baseline
   - Multi-NIC: Should scale linearly with number of active NICs
   - Target: 285 GB/s = 285,000 MB/s per NIC

2. **Message Rate (msg/s)**: Messages per second
   - Lower for large buffers (fewer messages needed)
   - Higher for small buffers (more messages needed)

3. **Latency (us)**: Time for message completion
   - Increases with buffer size
   - Should remain reasonable (<1000 us for optimal performance)

### What to Look For

**Good Performance Indicators**:
- Bandwidth increases proportionally with multi-rail configuration
- Test 2 (1GB) shows 30-50x improvement over single NIC
- Test 3-5 (8GB) show 900-1000x improvement over single NIC
- Stable performance across iterations (low variation)

**Performance Issues**:
- Bandwidth doesn't scale with multiple NICs
- High latency (>1000 us for large buffers)
- Large variation between iterations
- Error messages about device initialization

## Monitoring Active NICs

To verify which NICs are actually being used during a test, you can monitor EFA device activity:

On the client or server pod during a test:
```bash
# Watch network device statistics
watch -n 1 'cat /sys/class/infiniband/*/ports/1/counters/port_xmit_data'

# Or use EFA-specific monitoring
efa-info
```

Expected: During multi-NIC tests, you should see multiple devices showing activity.

## Troubleshooting

### Issue: Low Performance on Multi-NIC Tests

**Possible Causes**:
1. Only one NIC is being used (check with monitoring)
2. UCX not compiled with multi-rail support
3. EFA devices not properly configured
4. GPU memory bandwidth bottleneck

**Solutions**:
- Verify all 32 EFA devices are visible: `ls /sys/class/infiniband/`
- Check UCX info: `ucx_info -d`
- Ensure UCX_NET_DEVICES=all is set
- Try explicit device list instead of "all"

### Issue: "No such device" Errors

**Possible Causes**:
- EFA device not available in pod
- Incorrect device name
- EFA device plugin not running

**Solutions**:
- Check EFA devices: `ls /sys/class/infiniband/`
- Verify pod has EFA resource limit
- Check device plugin status: `kubectl get pods -n kube-system | grep efa`

### Issue: CUDA Errors

**Possible Causes**:
- GPU not accessible in pod
- CUDA version mismatch
- Insufficient GPU memory

**Solutions**:
- Check GPU: `nvidia-smi`
- Verify CUDA: `nvcc --version`
- Ensure pod has GPU resource limit

### Issue: Connection Timeout

**Possible Causes**:
- Server not started first
- Wrong IP address
- Port already in use
- Network policy blocking traffic

**Solutions**:
- Always start server before client
- Verify server IP: `hostname -i`
- Use different port number
- Check Kubernetes network policies

## Performance Optimization Tips

1. **Buffer Size**: Use 8GB buffers for maximum throughput
2. **Warmup**: Include warmup iterations (-w 20) to stabilize performance
3. **Iterations**: Run enough iterations (-n 50) for reliable measurements
4. **Rail Configuration**: Start with UCX_MAX_RNDV_RAILS=32
5. **Transport Order**: Put faster transports first (srd before others)
6. **Device Selection**: Use "all" for auto-detection or explicit list for control

## Known Limitations

1. **P5 Instance Requirement**: Full 32-NIC configuration requires P5 instances
2. **GPU Memory Bandwidth**: May bottleneck before reaching theoretical network maximum
3. **UCX Version**: Requires recent UCX version with SRD and multi-rail support
4. **EFA Driver**: Requires EFA driver with SRD support (1.x series)

## Comparison with Other Benchmarks

| Benchmark Type | Transport | Expected Performance | Use Case |
|----------------|-----------|---------------------|----------|
| UCX Native (this) | SRD direct | 285 GB/s per NIC | Baseline network capability |
| NIXL + LIBFABRIC | EFA provider | 46.48 GB/s | Production GPU-to-GPU transfers |
| NIXL + UCX | UCX backend | 0.85 GB/s | Comparison only (limited) |
| Full Dynamo | NIXL + backend | TBD | End-to-end inference performance |

## Additional Resources

- [UCX Documentation](https://openucx.readthedocs.io/)
- [AWS EFA Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html)
- [UCX Environment Variables](https://openucx.readthedocs.io/en/master/running.html#environment-variables)
- [UCX Performance Tuning](https://openucx.readthedocs.io/en/master/faq.html#performance-tuning)

## Contributing

When adding new test configurations:
1. Add the test to `run-ucx-test.sh`
2. Document expected results in this README
3. Include rationale for the configuration
4. Save results with timestamps in `results/` directory

## Results Directory

Test results are automatically saved to `results/ucx-test-TIMESTAMP.log` with:
- Full test configuration
- Commands used
- Environment variables
- Timestamps
- Performance observations

Review these files to track performance across different configurations and over time.
