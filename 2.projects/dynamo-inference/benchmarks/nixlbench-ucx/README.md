# NIXL UCX Backend Benchmark

## Overview

This directory contains benchmarks for testing NIXL with the UCX backend. **This backend is provided for comparison purposes only and is NOT recommended for production use.**

## Known Issues

### 1. ETCD URI Validation Error

The UCX backend frequently fails with the error:
```
target uri is not valid
```

This error occurs during ETCD initialization and prevents the distributed setup from completing.

### 2. Poor Performance

When the UCX backend does work, it achieves significantly worse performance than alternatives:

- **UCX Backend**: ~0.85 GB/s
- **LIBFABRIC Backend**: ~18 GB/s (21x faster!)

### 3. Stability Issues

The UCX backend has known stability issues including:
- Intermittent ETCD connection failures
- UCX library initialization errors
- CUDA IPC setup failures
- Unpredictable crashes during long-running tests

## Performance Comparison

| Backend | Bandwidth | Stability | Production Ready |
|---------|-----------|-----------|------------------|
| LIBFABRIC | ~18 GB/s | Excellent | ✅ Yes |
| UCX | ~0.85 GB/s | Poor | ❌ No |

## Usage

### Basic Test (May Fail)

```bash
./run-ucx-backend-test.sh
```

This will likely fail with ETCD errors.

### With Workaround

```bash
./run-ucx-backend-test.sh --with-workaround
```

This applies DRAM-based workarounds (see `workaround.sh` for details) which may improve stability but still shows poor performance.

### Manual Workarounds

For more control over workarounds:

```bash
source ./workaround.sh
./run-ucx-backend-test.sh
```

## What This Test Does

1. Starts an ETCD server for distributed coordination
2. Configures UCX with `tcp,cuda_copy,cuda_ipc` transport
3. Runs multi-process all-reduce benchmark
4. Measures bandwidth across 2 GPUs
5. Compares results with LIBFABRIC baseline

## Expected Results

### If Test Succeeds

```
NIXL UCX Backend Benchmark Results
====================================
Backend: UCX
Transport: tcp,cuda_copy,cuda_ipc
World Size: 2
Tensor Size: 1024 MB
Bandwidth: 0.85 GB/s

NOTE: Expected performance with UCX is ~0.85 GB/s
      This is significantly worse than LIBFABRIC (~18 GB/s)
      UCX backend is NOT recommended for production use
```

### If Test Fails (Common)

```
ERROR: Failed to initialize process group
This is the common 'target uri is not valid' ETCD error

Common UCX backend issues:
  1. 'target uri is not valid' ETCD error
  2. UCX library initialization failures
  3. CUDA IPC setup failures

Try running with workaround: ./run-ucx-backend-test.sh --with-workaround
Or use LIBFABRIC backend instead (much better performance)
```

## Troubleshooting

### ETCD Connection Errors

If you see "target uri is not valid" errors:

1. Check ETCD is running:
   ```bash
   curl http://127.0.0.1:29501/health
   ```

2. Verify ETCD logs:
   ```bash
   cat /tmp/etcd-nixl-ucx.log
   ```

3. Try the DRAM workaround:
   ```bash
   ./run-ucx-backend-test.sh --with-workaround
   ```

### UCX Library Errors

If you see UCX initialization errors:

1. Verify UCX is installed:
   ```bash
   python3 -c "import torch; print(torch.cuda.is_available())"
   ```

2. Check UCX environment variables:
   ```bash
   source ./workaround.sh
   env | grep UCX
   ```

### Low Performance

If the test runs but shows poor performance:

- **This is expected behavior** - UCX backend has inherently poor performance
- The workaround using DRAM may be even slower
- **Solution**: Use LIBFABRIC backend instead

## Workarounds

See `workaround.sh` for detailed workarounds including:

- Using DRAM instead of VRAM
- Alternative UCX transport configurations
- ETCD connection parameter tuning
- Disabling problematic UCX features

## Recommendations

### For Production Workloads

**Use LIBFABRIC backend instead:**

```bash
cd ../nixlbench-libfabric
./run-libfabric-backend-test.sh
```

LIBFABRIC provides:
- 21x better performance (18 GB/s vs 0.85 GB/s)
- Excellent stability
- No ETCD errors
- Production-ready reliability

### For Development/Testing

If you must test UCX:

1. Use the workaround mode
2. Expect failures and low performance
3. Have LIBFABRIC as a backup
4. Document any issues found

### For Comparison Studies

This benchmark is useful for:

- Comparing backend performance
- Understanding UCX limitations
- Validating LIBFABRIC superiority
- Academic/research purposes

## Files

- `run-ucx-backend-test.sh` - Main benchmark script
- `README.md` - This documentation
- `workaround.sh` - Workaround configurations and utilities

## Environment Variables

### UCX Configuration

```bash
UCX_TLS=tcp,cuda_copy,cuda_ipc  # Transport layers
UCX_NET_DEVICES=lo              # Network device (loopback)
UCX_MEMTYPE_CACHE=n             # Disable memory type cache
```

### NIXL Configuration

```bash
NIXL_STORE_TYPE=etcd                        # Store backend
NIXL_ETCD_ENDPOINTS=http://127.0.0.1:29501  # ETCD server
```

### Workaround Variables

```bash
NIXL_USE_DRAM=1      # Use DRAM instead of VRAM
NIXL_BUFFER_TYPE=cpu # Force CPU buffers
```

## Dependencies

- PyTorch with CUDA support
- UCX library (if available)
- ETCD server
- NIXL with UCX backend support

## Conclusion

The UCX backend demonstrates poor performance and reliability compared to LIBFABRIC. This benchmark exists to:

1. Document UCX limitations
2. Provide comparison data
3. Validate LIBFABRIC as the superior choice

**For all production workloads, use LIBFABRIC backend.**

## References

- LIBFABRIC benchmark: `../nixlbench-libfabric/`
- NIXL documentation: (add link)
- UCX project: https://www.openucx.org/
- Performance comparison data: See test outputs

## License

Same as parent project.
