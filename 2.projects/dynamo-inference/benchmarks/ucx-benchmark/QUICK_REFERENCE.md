# UCX Benchmark Quick Reference

## Quick Start

1. Deploy two pods on different nodes with GPU and EFA access
2. Update `SERVER_IP` in `run-ucx-test.sh` with server pod IP
3. Run `./run-ucx-test.sh` on client pod

## Test Configurations

### Test 1: Single NIC Baseline (Proven Working)

**SERVER:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=rdmap113s0:1
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -p 10100
```

**CLIENT:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=rdmap113s0:1
CUDA_VISIBLE_DEVICES=0 ucx_perftest <SERVER_IP> -t ucp_put_bw -m cuda -s 1073741824 -n 10 -p 10100
```

**Expected**: ~307 MB/s

---

### Test 2: Multi-NIC with 32 Rails (1GB)

**SERVER:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_NUM_PATHS=32
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -p 10101
```

**CLIENT:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_NUM_PATHS=32
CUDA_VISIBLE_DEVICES=0 ucx_perftest <SERVER_IP> -t ucp_put_bw -m cuda -s 1073741824 -n 10 -p 10101
```

**Expected**: ~9-10 GB/s

---

### Test 3: Multi-NIC Maximum Performance (8GB + GDR)

**SERVER:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_NUM_PATHS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -p 10102
```

**CLIENT:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_NUM_PATHS=32
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
CUDA_VISIBLE_DEVICES=0 ucx_perftest <SERVER_IP> -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p 10102
```

**Expected**: Up to 285 GB/s per active NIC

---

### Test 4: SRD-Specific Optimizations (8GB)

**SERVER:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_IB_NUM_PATHS=32
export UCX_SRD_TX_QUEUE_LEN=8192
export UCX_SRD_RX_QUEUE_LEN=8192
export UCX_SRD_MAX_NUM_EPS=256
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -p 10103
```

**CLIENT:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_IB_NUM_PATHS=32
export UCX_SRD_TX_QUEUE_LEN=8192
export UCX_SRD_RX_QUEUE_LEN=8192
export UCX_SRD_MAX_NUM_EPS=256
export UCX_RNDV_THRESH=8192
export UCX_ZCOPY_THRESH=32768
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest <SERVER_IP> -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p 10103
```

**Expected**: Up to 285 GB/s per active NIC

---

### Test 5: Rail Striping (8GB)

**SERVER:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_RNDV_SCHEME=put_rail
export UCX_RNDV_THRESH=1024
export UCX_SRD_SEG_SIZE=16384
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -p 10104
```

**CLIENT:**
```bash
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_RNDV_SCHEME=put_rail
export UCX_RNDV_THRESH=1024
export UCX_SRD_SEG_SIZE=16384
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest <SERVER_IP> -t ucp_put_bw -m cuda -s 8589934592 -n 50 -w 20 -p 10104
```

**Expected**: Up to 285 GB/s per active NIC

---

## Command Line Parameters

### ucx_perftest Common Options

- `-t ucp_put_bw`: Test type (PUT bandwidth)
- `-m cuda`: Use CUDA memory (GPU)
- `-s SIZE`: Message size in bytes
- `-n NUM`: Number of iterations
- `-w NUM`: Warmup iterations
- `-p PORT`: Port number

### Buffer Sizes

- `1073741824` = 1 GB
- `2147483648` = 2 GB
- `8589934592` = 8 GB

### Finding Server IP

On server pod:
```bash
hostname -i
```

### Monitoring Active NICs

During test:
```bash
# Watch all EFA devices
watch -n 1 'ls /sys/class/infiniband/ | xargs -I{} cat /sys/class/infiniband/{}/ports/1/counters/port_xmit_data'

# Count active devices
ls /sys/class/infiniband/ | wc -l
```

### Checking UCX Configuration

```bash
# List available transports
ucx_info -d

# Show UCX configuration
ucx_info -c

# Show active environment variables
env | grep UCX_
```

## Key Environment Variables

### Transport Configuration
- `UCX_TLS`: Transport layer selection (e.g., srd,cuda_copy,cuda_ipc)
- `UCX_NET_DEVICES`: Network devices to use (e.g., all, rdmap113s0:1)

### Multi-Rail Configuration
- `UCX_MAX_RNDV_RAILS`: Maximum rails for rendezvous protocol (large messages)
- `UCX_MAX_EAGER_RAILS`: Maximum rails for eager protocol (small messages)
- `UCX_IB_NUM_PATHS`: Number of parallel paths (may not apply to SRD)

### SRD-Specific
- `UCX_SRD_TX_QUEUE_LEN`: Transmit queue length
- `UCX_SRD_RX_QUEUE_LEN`: Receive queue length
- `UCX_SRD_MAX_NUM_EPS`: Maximum number of endpoints
- `UCX_SRD_SEG_SIZE`: Segment size for transfers

### Performance Tuning
- `UCX_RNDV_THRESH`: Threshold to switch to rendezvous protocol (bytes)
- `UCX_ZCOPY_THRESH`: Threshold for zero-copy transfers (bytes)
- `UCX_RNDV_SCHEME`: Rendezvous scheme (e.g., put_rail)

### Other
- `UCX_WARN_UNUSED_ENV_VARS`: Suppress warnings about unused variables (n/y)

## Troubleshooting

### No Performance Improvement with Multi-Rail

Check which devices are active:
```bash
ls /sys/class/infiniband/
```

Try explicit device list:
```bash
export UCX_NET_DEVICES=rdmap79s0,rdmap80s0,rdmap81s0,rdmap82s0  # etc.
```

### Connection Issues

1. Ensure server is started first
2. Verify server IP: `hostname -i`
3. Check port is not in use: `netstat -tuln | grep <PORT>`
4. Verify network connectivity: `ping <SERVER_IP>`

### CUDA Errors

1. Check GPU: `nvidia-smi`
2. Verify CUDA: `nvcc --version`
3. Ensure GPU 0 is available: `CUDA_VISIBLE_DEVICES=0 nvidia-smi`

## Performance Expectations

| Configuration | Expected Bandwidth | Speedup vs Single NIC |
|---------------|-------------------|----------------------|
| Single NIC | ~307 MB/s | 1x (baseline) |
| Multi-NIC 1GB | ~9-10 GB/s | ~30x |
| Multi-NIC 8GB | ~285 GB/s | ~900x |
| All 32 NICs | ~9 TB/s | ~28,000x |

Note: Actual performance depends on hardware, network topology, and GPU memory bandwidth.
