# awsi-efa-base:v1 — RDMA validation evidence

**Image:** `058264135704.dkr.ecr.us-east-2.amazonaws.com/awsi-efa-base:v1`
**Built from:** `Dockerfile.efa` (target `final`)
**Base:** `networking-base:v5` (EFA 1.48.0 / libfabric 2.4.0amzn3.0 / aws-ofi-nccl 1.19.0-1 NGC v1 / NCCL 2.30.3 / UCX 1.20.0 / NIXL 1.0.1)
**Tested on:** `ip-10-1-0-171.us-east-2.compute.internal` (p5en.48xlarge — H200 8× + 16 EFA NICs)
**Date:** 2026-04-25

## Build-time validation (inside image at /opt/tests/run-efa-tests.sh)

```
=== EFA Networking Validation Tests ===
--- Component presence ---
  PASS: libfabric
  PASS: fi_info
  PASS: GDRCopy
  PASS: UCX
  PASS: NIXL
  PASS: NIXL libfabric plugin
  PASS: NCCL
  PASS: aws-ofi-nccl
  PASS: nccl-tests
  PASS: kubectl

--- Library versions ---
fi_info: 2.4.0amzn3.0
# Library version: 1.20.0   (UCX)

--- GIN plugin symbols ---
  PASS: aws-ofi-nccl exports ncclGin symbols

--- Python packages ---
  PASS: python3 import nixl
  PASS: python3 import nemo_evaluator
  PASS: python3 import nvidia_resiliency_ext

=== Results: 13 passed, 0 failed ===
```

## Runtime RDMA validation (NCCL all_reduce_perf, single node, 8 GPUs)

### Provider + transport
```
NCCL INFO NET/OFI Initializing aws-ofi-nccl 1.19.0
NCCL INFO NET/OFI Using Libfabric version 2.4
NCCL INFO NET/OFI Using CUDA driver version 13000 with runtime 12090
NCCL INFO NET/OFI Plugin selected platform: AWS
NCCL INFO NET/OFI Configuring AWS-specific options
NCCL INFO NET/OFI Internode latency set at 35.0 us
NCCL INFO NET/OFI Using transport protocol RDMA (platform set)
NCCL INFO NET/OFI Selected provider is efa, fabric is efa-direct (found 16 nics)
```

### EFA NIC enumeration (selected)
```
NCCL INFO NET/OFI NIC group 0 device #0 0000:56:00.0
NCCL INFO NET/OFI NIC group 1 device #0 0000:58:00.0
NCCL INFO NET/OFI NIC group 2 device #0 0000:6f:00.0
NCCL INFO NET/OFI NIC group 3 device #0 0000:71:00.0
NCCL INFO NET/OFI NIC group 4 device #0 0000:88:00.0
NCCL INFO NET/OFI NIC group 5 device #0 0000:8a:00.0
... 16 NICs in 8 groups ...
```

### RDMA hw_counters (proof RDMA bytes increased)
```
AFTER the NCCL all_reduce (selected devices — full list in validate-efa-base.log):
  rdmap85s0   rdma_write_bytes = 147,122,355,539   (147 GB)
  rdmap86s0   rdma_write_bytes = 148,137,221,688   (148 GB)
  rdmap87s0   rdma_write_bytes = 146,430,505,704   (146 GB)
  rdmap88s0   rdma_write_bytes = 145,143,410,496   (145 GB)
  rdmap160s0  rdma_write_bytes = 142,290,693,788   (142 GB)
  rdmap161s0  rdma_write_bytes = 141,028,760,184   (141 GB)
  rdmap162s0  rdma_write_bytes = 141,251,749,040   (141 GB)
  rdmap163s0  rdma_write_bytes = 139,934,604,032   (139 GB)
```

### TCP-fallback sentinel
Grep for `NET/Socket`, `NCCL_SOCKET_IFNAME fallback`, `TCP transport` — **no match.**

## Result
```
RDMA_PATH_CONFIRMED: libfabric/EFA active
=== RDMA VALIDATION PASSED ===
```
