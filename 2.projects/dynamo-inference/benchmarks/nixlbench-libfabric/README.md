# NIXL LIBFABRIC Benchmark Suite

Benchmark suite for testing NVIDIA NIXL (Network Interface for X-link) with LIBFABRIC backend over AWS Elastic Fabric Adapter (EFA). This configuration has been validated to achieve **46.48 GB/s** GPU-to-GPU RDMA bandwidth on P5 instances.

## Performance Summary

| Backend | Memory Type | P2P Setting | Bandwidth | Status |
|---------|-------------|-------------|-----------|--------|
| **LIBFABRIC** | VRAM-to-VRAM | **Enabled** | **46.48 GB/s** | ✅ **Validated** |
| LIBFABRIC | DRAM-to-DRAM | N/A | 40-45 GB/s | ✅ Good |
| UCX | VRAM-to-VRAM | N/A | 0.85 GB/s | ❌ Poor |

## Quick Start

### Prerequisites
1. Kubernetes cluster with EFA-enabled instances (P5, P4d, or P4de)
2. Two benchmark pods deployed with anti-affinity
3. ETCD coordination service running
4. Proper EFA and GPU device allocation

### Running the Benchmark

```bash
# 1. Make script executable
chmod +x run-libfabric-test.sh

# 2. Run the benchmark
./run-libfabric-test.sh
```

The script will automatically:
- Verify all prerequisites
- Clean ETCD for fresh state
- Verify pod placement (different nodes)
- Start Pod 2 first, wait 10 seconds
- Start Pod 1 and display results
- Save detailed logs and test report

## Critical Configuration

### 1. P2P Setting (CRITICAL for P5 Instances)

```bash
FI_HMEM_DISABLE_P2P=0  # P2P ENABLED
```

**⚠️ IMPORTANT**: This setting is **REQUIRED** for optimal performance on P5 instances. It enables GPU Direct RDMA for peer-to-peer memory transfers across physical nodes.

- **With P2P Enabled (0)**: 46+ GB/s bandwidth ✅
- **With P2P Disabled (1)**: Significantly lower bandwidth ❌

### 2. LIBFABRIC Provider

```bash
FI_PROVIDER=efa  # Use EFA provider
```

The EFA (Elastic Fabric Adapter) provider is optimized for AWS networking and provides the best performance.

### 3. Memory Type

```bash
--initiator_seg_type VRAM --target_seg_type VRAM
```

VRAM-to-VRAM (GPU Direct) transfers provide the highest bandwidth by bypassing host memory.

### 4. Startup Sequence

**Critical**: Start pods in the correct order:
1. Start **Pod 2** (target) first
2. Wait **10 seconds** for ETCD registration
3. Start **Pod 1** (initiator)

### 5. ETCD Cleanup

Always clean ETCD before each test run to ensure reliable results:

```bash
kubectl exec -it statefulset/etcd -- etcdctl del "" --from-key=true --prefix
```

The benchmark script does this automatically.

## Pod Configuration

### Resource Requirements

```yaml
resources:
  requests:
    nvidia.com/gpu: 1
    vpc.amazonaws.com/efa: 1
    memory: 32Gi
    cpu: 8
    hugepages-2Mi: 2Gi
  limits:
    nvidia.com/gpu: 1
    vpc.amazonaws.com/efa: 1
    memory: 32Gi
    cpu: 8
    hugepages-2Mi: 2Gi
```

### Anti-Affinity (Required)

Pods must run on different physical nodes for cross-node testing:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: benchmark-group
          operator: In
          values:
          - nixl-efa-test
      topologyKey: kubernetes.io/hostname
```

### Security Context

```yaml
securityContext:
  capabilities:
    add:
    - IPC_LOCK       # Required for RDMA
    - SYS_PTRACE     # Required for debugging
  privileged: true   # Required for GPU Direct RDMA
```

## Expected Performance Results

### Bandwidth Scaling (Validated on P5 Instances)

| Block Size | Bandwidth | Latency (μs) | Notes |
|------------|-----------|--------------|-------|
| 4 KB | 0.08 GB/s | 49.2 | Small transfers |
| 1 MB | 14.12 GB/s | 74.3 | Good scaling |
| 16 MB | 41.06 GB/s | 408.6 | Near-peak |
| **67 MB** | **46.48 GB/s** | **1443.8** | **Peak performance** |

### Performance Characteristics

- **Peak bandwidth**: 46+ GB/s at 67 MB block size
- **Good scaling**: Bandwidth increases with block size
- **Low latency**: Sub-50μs for small transfers
- **Optimal for**: Large ML model transfers, distributed training

## Test Artifacts

After running the benchmark, logs are saved to `/tmp/nixlbench-libfabric-logs-<timestamp>/`:

```
├── test-report.txt          Main test log with summary
├── node1-output.log         Initiator logs with results
├── node2-output.log         Target logs
├── fi_info-node1.txt        EFA provider information
├── gpu-info-node1.txt       GPU device listing
└── efa-devices-node1.txt    EFA device details
```

## Troubleshooting

### Issue: Pods on Same Node

**Problem**: Anti-affinity not working, both pods on same node.

**Solution**:
```bash
# Check pod placement
kubectl get pods -o wide | grep nixl-bench

# Verify anti-affinity label
kubectl get pods --show-labels | grep benchmark-group

# Redeploy with correct labels
kubectl delete pod nixl-bench-node1 nixl-bench-node2
kubectl apply -f pod-config.yaml
```

### Issue: Low Bandwidth (<10 GB/s)

**Problem**: Performance significantly below expected 46 GB/s.

**Root Causes & Solutions**:

1. **P2P Disabled**: Check if P2P is enabled
   ```bash
   # Verify P2P setting in logs
   grep "hmem_disable_p2p" /tmp/nixlbench-libfabric-logs-*/node1-output.log
   # Should show: hmem_disable_p2p=0
   ```

2. **Same Node**: Pods on same physical node
   ```bash
   # Verify different nodes
   kubectl get pod nixl-bench-node1 -o jsonpath='{.spec.nodeName}'
   kubectl get pod nixl-bench-node2 -o jsonpath='{.spec.nodeName}'
   ```

3. **No EFA Device**: EFA device not allocated
   ```bash
   # Check EFA allocation
   kubectl describe pod nixl-bench-node1 | grep efa
   kubectl exec nixl-bench-node1 -- ls /dev/infiniband
   ```

4. **Stale ETCD State**: ETCD not cleaned before test
   ```bash
   # Clean ETCD manually
   kubectl exec -it statefulset/etcd -- etcdctl del "" --from-key=true --prefix
   ```

### Issue: Connection Timeout

**Problem**: Pods cannot connect to each other or ETCD.

**Solution**:
```bash
# Verify ETCD service
kubectl get service etcd-service

# Check pod connectivity
kubectl exec nixl-bench-node1 -- curl -v http://etcd-service:2379/health

# Check pod networking
kubectl exec nixl-bench-node1 -- ip addr show
```

### Issue: CUDA Errors

**Problem**: GPU memory allocation failures.

**Solution**:
```bash
# Check GPU availability
kubectl exec nixl-bench-node1 -- nvidia-smi

# Check GPU allocation
kubectl describe pod nixl-bench-node1 | grep -A 5 "nvidia.com/gpu"

# Restart pods if GPU is stuck
kubectl delete pod nixl-bench-node1 nixl-bench-node2
kubectl apply -f pod-config.yaml
```

## Advanced Configuration

### Custom Memory Types

Test different memory transfer types:

```bash
# VRAM-to-VRAM (default, highest performance)
./run-libfabric-test.sh

# DRAM-to-DRAM (host memory)
# Edit run-libfabric-test.sh and change:
# --initiator_seg_type DRAM --target_seg_type DRAM
```

### Custom Log Levels

For debugging, increase libfabric log verbosity:

```bash
# Edit run-libfabric-test.sh and change:
FI_LOG_LEVEL=debug  # Options: warn, info, debug, trace
```

### P2P Comparison Test

Compare performance with P2P enabled vs disabled:

```bash
# Test 1: P2P Enabled (default)
./run-libfabric-test.sh

# Test 2: P2P Disabled
# Edit run-libfabric-test.sh and change:
# FI_HMEM_DISABLE_P2P=1
./run-libfabric-test.sh
```

## Integration with Awesome Inference

This benchmark is part of the Awesome Inference project:

```
awsome-inference/
└── 2.projects/
    └── dynamo-inference/
        └── benchmarks/
            └── nixlbench-libfabric/  # This directory
```

## Backend Comparison

### LIBFABRIC

- **Performance**: 46+ GB/s
- **Native EFA support**: Optimized provider
- **GPU Direct RDMA**: Full P2P support
- **Stability**: Tested with EFA workloads
- **AWS optimization**: Designed for EKS/ECS

### UCX

- **Performance**: ~0.85 GB/s on EFA
- **EFA optimization**: Limited compared to LIBFABRIC
- **Alternative environments**: InfiniBand support

## Technical Details

### LIBFABRIC Configuration

Key environment variables used by the benchmark:

```bash
FI_PROVIDER=efa                  # EFA provider
FI_HMEM_DISABLE_P2P=0            # Enable GPU P2P (CRITICAL!)
FI_LOG_LEVEL=info                # Logging verbosity
FI_EFA_ENABLE_SHM_TRANSFER=0     # Disable SHM for cross-node
```

### EFA Provider Settings

Default EFA provider settings (from fi_info):

```
enable_shm_transfer=0     # SHM disabled for cross-node
recvwin_size=8192        # Receive window size
cq_size=16384            # Completion queue size
tx_size=8192             # Transmit queue size
rx_size=8192             # Receive queue size
mr_cache_monitor=disabled # Memory registration cache
```

### HMEM (Heterogeneous Memory) Support

LIBFABRIC supports multiple memory types:

- ✅ **CUDA**: NVIDIA GPUs (enabled)
- ✅ **CUDA dmabuf**: Direct memory buffer support
- ❌ **ROCR**: AMD GPUs (not supported on AWS)
- ❌ **ZE**: Intel GPUs (not supported on AWS)

## Performance Tuning

### 1. Instance Selection

Best instance types for NIXL benchmarking:

| Instance | GPUs | EFA | Memory | Recommended |
|----------|------|-----|--------|-------------|
| **p5.48xlarge** | 8x H100 | 32x | 2TB | ✅ **Best** |
| p4d.24xlarge | 8x A100 | 4x | 1.1TB | ✅ Good |
| p4de.24xlarge | 8x A100 80GB | 4x | 1.1TB | ✅ Good |

### 2. Network Optimization

For production workloads:

```yaml
# Increase EFA allocation if available
resources:
  requests:
    vpc.amazonaws.com/efa: 4  # Use all available EFA devices
```

### 3. HugePages Tuning

For very large transfers:

```yaml
resources:
  requests:
    hugepages-2Mi: 4Gi  # Increase from 2Gi
  limits:
    hugepages-2Mi: 4Gi
```

### 4. Block Size Selection

Choose block size based on your workload:

- **Small messages (<1 MB)**: Low latency, ~0.1-14 GB/s
- **Medium messages (1-16 MB)**: Good balance, ~14-41 GB/s
- **Large messages (>16 MB)**: Peak bandwidth, ~41-46 GB/s

## References

### Documentation

- [NVIDIA NIXL Documentation](https://github.com/NVIDIA/nccl)
- [AWS EFA Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html)
- [Libfabric Documentation](https://ofiwg.github.io/libfabric/)
- [Libfabric EFA Provider](https://github.com/ofiwg/libfabric/tree/main/prov/efa)

### Related Benchmarks

- UCX Benchmark: `../ucx-benchmark/`
- Full NIXL EFA Suite: `/home/ubuntu/nixl-efa-benchmark/`

## Support

### Getting Help

1. **Check logs**: Review test-report.txt for detailed diagnostics
2. **Verify prerequisites**: Ensure EFA, GPU, and ETCD are properly configured
3. **Review troubleshooting**: See troubleshooting section above
4. **Compare with expected**: Your results should be within 10% of 46.48 GB/s

### Common Issues

- **Low bandwidth**: Check P2P setting and pod placement
- **Connection errors**: Verify ETCD and network connectivity
- **Resource errors**: Check EFA/GPU allocation and HugePages

## Contributing

Contributions welcome! Areas of interest:

- Additional instance type testing
- Performance optimizations
- Enhanced error handling
- Documentation improvements

## License

MIT License - See main project LICENSE file.

---

## Changelog

### Version 1.0 (2025-11-20)

- Initial release
- Validated 46.48 GB/s performance on P5 instances
- Comprehensive troubleshooting guide
- Automatic ETCD cleanup
- Detailed logging and reporting

---

**Last Updated**: November 20, 2025
**Validated On**: AWS EKS with p5.48xlarge (H100 GPUs)
**Peak Performance**: 46.48 GB/s GPU-to-GPU with LIBFABRIC
**Status**: ✅ Production Ready
