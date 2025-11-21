# nixlbench ETCD URI Validation Fix

## Problem
nixlbench fails with error: "Failed to store agent target prefix key in etcd: the target uri is not valid" when DNS resolution returns empty, even though ETCD is fully accessible.

## Root Cause
The `etcd-cpp-apiv3` library (v0.15.4) performs overly strict URI validation in `src/SyncClient.cpp` that fails when DNS resolution returns empty.

## Solution
Apply patch `etcd-uri-fix.patch` that adds environment variable bypass for strict URI validation.

## Quick Start

### Option 1: Apply Patch to Existing Image
```bash
# Apply the patch to any existing dynamo-trtllm image
./scripts/apply-nixlbench-patch.sh \
  "058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full" \
  "dynamo-trtllm:fixed"
```

### Option 2: Use Pre-patched Dockerfile
```bash
docker build -f docker/Dockerfile.nixlbench-patch \
  --build-arg BASE_IMAGE=your-base-image \
  -t your-image:fixed .
```

### Option 3: Manual Application
1. Set environment variable: `export ETCD_CPP_API_DISABLE_URI_VALIDATION=1`
2. Use a container with the patched library

## Files
- `docker/etcd-uri-fix.patch` - The patch for etcd-cpp-apiv3
- `docker/Dockerfile.nixlbench-patch` - Dockerfile to apply the patch
- `scripts/apply-nixlbench-patch.sh` - Script to patch existing images

## Test Results
After applying the fix, nixlbench achieves excellent performance:
- Peak: 12.3 GB/s with LIBFABRIC backend (40x improvement)
- Consistent operation without URI validation errors

## Related Issue
Fixes: https://github.com/ai-dynamo/nixl/issues/1044