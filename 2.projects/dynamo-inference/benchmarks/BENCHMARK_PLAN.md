# Dynamo Benchmark Suite Plan

## Overview
Complete benchmarking suite for Dynamo with UCX, NIXL-UCX, and NIXL-LIBFABRIC backends.

## Folder Structure
```
/home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks/
├── BENCHMARK_PLAN.md                    # This file
├── deploy-cluster.sh                    # Main cluster deployment script
├── run-all-benchmarks.sh               # Master script to run all tests
├── ucx-benchmark/                      # Native UCX perftest
│   ├── run-ucx-test.sh
│   ├── README.md
│   └── results/
├── nixlbench-libfabric/                # NIXL with LIBFABRIC backend (46 GB/s)
│   ├── run-libfabric-test.sh
│   ├── pod-config.yaml
│   ├── README.md
│   └── results/
├── nixlbench-ucx/                      # NIXL with UCX backend
│   ├── run-ucx-backend-test.sh
│   ├── pod-config.yaml
│   ├── README.md
│   └── results/
└── dynamo-cluster/                     # Full Dynamo deployment
    ├── dynamo-deployment.yaml
    ├── etcd-service.yaml
    └── helper-scripts/
```

## Key Findings from Analysis

### 1. WORKING LIBFABRIC Configuration (46.48 GB/s)
- **Image**: `nixl-aligned:0.7.1-bench` (from /home/ubuntu/nixl-efa-benchmark)
- **Critical Setting**: `FI_HMEM_DISABLE_P2P=0` for P5 instances
- **Backend**: LIBFABRIC with EFA provider
- **Memory**: VRAM-to-VRAM transfers

### 2. UCX Native Test (285 GB/s single NIC)
- Already working configuration in `/home/ubuntu/awsome-inference/2.projects/dynamo-inference/scripts/`
- Can scale to 32 NICs for ~9 TB/s theoretical maximum
- Uses SRD transport on AWS EFA

### 3. Dynamo Cluster Configuration
- Working TRT-LLM deployment in `/home/ubuntu/dynamo-experiment/trtllm-full-dynamograph-corrected.yaml`
- Platform deployment uses Helm with storage overrides
- Helper scripts available in `trtllm-helpers.sh`

## Execution Plan

### Phase 1: Setup Infrastructure
1. Deploy ETCD coordination service (required for nixlbench)
2. Verify EFA device plugin is running
3. Check node labels and GPU availability

### Phase 2: Run Benchmarks (in order)

#### Test 1: UCX Native Benchmark
- **Purpose**: Establish baseline performance
- **Expected**: 285 GB/s per NIC, up to 9 TB/s with 32 NICs
- **Command**: Direct ucx_perftest between pods

#### Test 2: NIXL with LIBFABRIC Backend
- **Purpose**: Production-ready benchmark
- **Expected**: 46.48 GB/s GPU-to-GPU
- **Command**: nixlbench with LIBFABRIC backend
- **Note**: This is the RECOMMENDED configuration

#### Test 3: NIXL with UCX Backend
- **Purpose**: Comparison only
- **Expected**: 0.85 GB/s (known performance limitation)
- **Command**: nixlbench with UCX backend
- **Note**: May fail with ETCD URI errors

### Phase 3: Deploy Full Dynamo
- Deploy disaggregated Dynamo cluster
- Run end-to-end inference benchmarks
- Compare with baseline network performance

## Critical Success Factors

1. **Use the correct image**: `nixl-aligned:0.7.1-bench`
2. **Enable P2P for LIBFABRIC**: Set `FI_HMEM_DISABLE_P2P=0`
3. **Pod anti-affinity**: Ensure pods run on different nodes
4. **ETCD timing**: Start node2 first, wait 7-10 seconds, then node1
5. **Clean ETCD between tests**: `etcdctl del "" --prefix`

## Files to Copy

From `/home/ubuntu/nixl-efa-benchmark/`:
- `kubernetes/` - All YAML files
- `scripts/` - All bash scripts
- `results/libfabric-46.48gbps-p2p-enabled.md` - Reference results

From `/home/ubuntu/dynamo-experiment/`:
- `trtllm-full-dynamograph-corrected.yaml`
- `trtllm-helpers.sh`
- `trtllm-benchmark.sh`

## Expected Results

| Benchmark | Backend | Expected Performance | Status |
|-----------|---------|---------------------|--------|
| UCX Native | N/A | 285 GB/s per NIC | ✅ Proven |
| NIXL | LIBFABRIC | 46.48 GB/s | ✅ Proven |
| NIXL | UCX | 0.85 GB/s | ⚠️ Limited |

## Next Steps

1. Create folder structure
2. Copy working configurations
3. Adapt scripts for new paths
4. Run benchmarks in sequence
5. Document results