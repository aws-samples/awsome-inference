# UCX Benchmark Pre-Flight Checklist

Use this checklist before running the UCX benchmark tests.

## Prerequisites Checklist

### Infrastructure Requirements

- [ ] Kubernetes cluster is running
- [ ] At least 2 GPU nodes available (for cross-node testing)
- [ ] Nodes have EFA adapters installed
- [ ] EFA device plugin is deployed and running
- [ ] NVIDIA GPU device plugin is deployed and running

### Verify EFA Device Plugin

```bash
kubectl get pods -n kube-system | grep efa
```

Expected: One efa-device-plugin pod per node in Running state

### Verify GPU Device Plugin

```bash
kubectl get pods -n kube-system | grep nvidia
```

Expected: One nvidia-device-plugin pod per node in Running state

### Node Requirements

- [ ] Nodes are labeled correctly for GPU and EFA
- [ ] P5 instances (or equivalent) with 32 EFA devices per node
- [ ] CUDA drivers installed on nodes
- [ ] EFA drivers installed on nodes

### Verify Node Resources

```bash
kubectl describe nodes | grep -A 5 "Allocatable:"
```

Expected to see:
- `nvidia.com/gpu: N` (where N > 0)
- `vpc.amazonaws.com/efa: 32` (or number of EFA devices)

## Pod Deployment Checklist

### Container Requirements

- [ ] Container image includes UCX tools (ucx_perftest)
- [ ] Container image includes CUDA runtime
- [ ] Container image includes EFA libraries
- [ ] Container has network access between pods

### Resource Requests

Pod YAML should include:
```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    vpc.amazonaws.com/efa: 1  # or more for multi-rail
```

### Pod Placement

- [ ] Server pod deployed on node 1
- [ ] Client pod deployed on node 2 (different from server)
- [ ] Pod anti-affinity configured (if using pod specs)

### Verify Pod Placement

```bash
kubectl get pods -o wide
```

Expected: Pods running on different nodes

## Pre-Test Verification

### On Each Pod

#### 1. Verify GPU Access

```bash
nvidia-smi
```

Expected: GPU visible and available

#### 2. Verify EFA Devices

```bash
ls /sys/class/infiniband/
```

Expected: Multiple rdmap* devices (32 on P5 instances)

#### 3. Verify UCX Installation

```bash
which ucx_perftest
```

Expected: Path to ucx_perftest binary

#### 4. Verify UCX Info

```bash
ucx_info -d
```

Expected: Output showing available transports including SRD

#### 5. Verify Network Connectivity

From client pod:
```bash
ping <SERVER_POD_IP>
```

Expected: Successful ping responses

### Get Server Pod IP

On server pod:
```bash
hostname -i
```

Record this IP: ___________________

### Update Script Configuration

- [ ] Edit `run-ucx-test.sh`
- [ ] Update `SERVER_IP` variable with server pod IP
- [ ] Save the file

## Environment Setup

### On Both Pods (Server and Client)

#### 1. Set CUDA Visible Devices

```bash
export CUDA_VISIBLE_DEVICES=0
```

#### 2. Verify CUDA Device

```bash
nvidia-smi -L
```

Expected: GPU 0 visible

## Test Execution Checklist

### Before Starting Tests

- [ ] Server pod ready and waiting
- [ ] Client pod ready with test script
- [ ] Monitoring tools ready (if using)
- [ ] Results directory exists and is writable
- [ ] Have access to both pod terminals

### During Test Execution

- [ ] Start server command BEFORE client
- [ ] Wait for server "Waiting for connection" message
- [ ] Then start client command
- [ ] Monitor for completion (may take several minutes for 8GB tests)
- [ ] Record results before proceeding to next test

### Test Sequence

For each test:

1. [ ] Read test configuration from script output
2. [ ] Set environment variables on server pod
3. [ ] Start server command
4. [ ] Wait for "Waiting for connection" message
5. [ ] Set environment variables on client pod
6. [ ] Start client command
7. [ ] Wait for test completion
8. [ ] Record bandwidth results
9. [ ] Press Enter to continue to next test

## Results Recording

For each test, record:

- [ ] Test number and name
- [ ] Bandwidth (MB/s or GB/s)
- [ ] Message rate (msg/s)
- [ ] Latency (us)
- [ ] Any errors or warnings
- [ ] Number of active NICs (if monitoring)

## Troubleshooting Checklist

### If Test Fails to Connect

- [ ] Verify server is running first
- [ ] Check server IP is correct
- [ ] Verify port is not in use
- [ ] Check network policies allow traffic
- [ ] Verify both pods are in Running state

### If Performance is Lower Than Expected

- [ ] Check only one NIC is being used (Test 1 baseline)
- [ ] Verify multi-rail configuration is set
- [ ] Check if UCX_NET_DEVICES=all is recognized
- [ ] Monitor EFA device counters during test
- [ ] Verify GPU memory bandwidth is not bottleneck

### If CUDA Errors Occur

- [ ] Verify nvidia-smi shows GPU
- [ ] Check CUDA_VISIBLE_DEVICES is set
- [ ] Verify container has GPU access
- [ ] Check GPU memory is not exhausted

### If "No Device" Errors Occur

- [ ] Verify EFA devices exist: `ls /sys/class/infiniband/`
- [ ] Check pod has EFA resource limit
- [ ] Verify EFA device plugin is running
- [ ] Check device name matches available devices

## Post-Test Checklist

- [ ] Results saved to results/ directory
- [ ] Results file has timestamp
- [ ] All test configurations documented
- [ ] Performance compared to expectations
- [ ] Anomalies or issues documented
- [ ] Cleanup pods if needed

## Quick Command Reference

### Start Test Suite
```bash
cd /home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks/ucx-benchmark
./run-ucx-test.sh
```

### View Results
```bash
ls -lt results/
cat results/ucx-test-*.log | less
```

### Monitor EFA Devices During Test
```bash
watch -n 1 'ls /sys/class/infiniband/ | xargs -I{} cat /sys/class/infiniband/{}/ports/1/counters/port_xmit_data'
```

### Clean Up Test Pods
```bash
kubectl delete pod ucx-server
kubectl delete pod ucx-client
```

## Expected Performance Summary

| Test | Buffer | Configuration | Expected Bandwidth |
|------|--------|--------------|-------------------|
| 1 | 1 GB | Single NIC | ~307 MB/s |
| 2 | 1 GB | Multi-NIC | ~9-10 GB/s |
| 3 | 8 GB | Multi-NIC + GDR | ~285 GB/s |
| 4 | 8 GB | SRD Optimized | ~285 GB/s |
| 5 | 8 GB | Rail Striping | ~285 GB/s |

## Support and Documentation

- Full documentation: See `README.md`
- Quick reference: See `QUICK_REFERENCE.md`
- Test script: See `run-ucx-test.sh`
- Results: See `results/` directory

---

**Ready to Run Tests?**

Once all checkboxes are complete, you're ready to execute:
```bash
./run-ucx-test.sh
```

Good luck with your benchmarking!
