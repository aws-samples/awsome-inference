# A10G Dynamo Module Fix

**Date**: 2025-11-17
**Issue**: ModuleNotFoundError when running `python -m dynamo.vllm` or `python -m dynamo.trtllm`
**Affected Images**: `dynamo-trtllm-efa:slim-a10g`, `dynamo-vllm-efa:slim-a10g`

---

## Problem

Published A10G images fail with:
```
ModuleNotFoundError: No module named 'dynamo'
```

## Root Cause

Dockerfile bug: `VIRTUAL_ENV` variable used in `PATH` before being defined.

**Broken code** (Dockerfile.dynamo-vllm line 295, Dockerfile.dynamo-trtllm line 228):
```dockerfile
ENV PATH="${VIRTUAL_ENV}/bin:/opt/hpcx/ompi/bin:..."  # VIRTUAL_ENV is empty!
# ... later ...
ENV VIRTUAL_ENV=/opt/dynamo/venv  # Too late!
```

## Solution

Reorder ENV statements to define `VIRTUAL_ENV` **before** using it:

```dockerfile
# Define VIRTUAL_ENV first
ENV VIRTUAL_ENV=/opt/dynamo/venv

# Then use it in PATH
ENV PATH="${VIRTUAL_ENV}/bin:/opt/hpcx/ompi/bin:..."
```

## Fixed Files

- `Dockerfile.dynamo-vllm` (lines 281-309)
- `Dockerfile.dynamo-trtllm` (lines 214-241)

## Rebuild Instructions

```bash
cd /home/ubuntu/awsome-inference/2.projects/dynamo-inference

# Rebuild vLLM image
./build_vllm.sh slim

# Rebuild TensorRT-LLM image
./build_trtllm.sh slim

# Test the fix
./scripts/test-dynamo-modules.sh
```

## Validation

After rebuild, verify:
```bash
docker run --rm dynamo-vllm-efa:slim-a10g python -m dynamo.vllm --version
docker run --rm dynamo-trtllm-efa:slim-a10g python -m dynamo.trtllm --version
```

Both should execute without ModuleNotFoundError.

---

**Status**: Fixed in Dockerfiles, pending rebuild and republish
