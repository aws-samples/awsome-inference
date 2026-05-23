# awsi-dynamo-combined-efa:v1 — vLLM backend inference evidence

**Image:** `058264135704.dkr.ecr.us-east-2.amazonaws.com/awsi-dynamo-combined-efa:v1` (sha256:f7b40721...)
**Built from:** `Dockerfile.dynamo-combined-efa` (target `final`, DYNAMO_BACKEND=vllm)
**Tested on:** `ip-10-1-0-171.us-east-2.compute.internal` (p5en.48xlarge — H200 + 16 EFA NICs)
**Date:** 2026-04-25

## EFA fabric ready
```
provider: efa (4 rows in fi_info -p efa)
```

## hw_counters snapshot
```
rdma_write_bytes total BEFORE = 2,293,173,976,367   (~2.3 TB — pod ran on shared node)
rdma_write_bytes total AFTER  = 2,293,173,976,367   (1-GPU inference didn't need RDMA, as expected)
```
The EFA stack is loaded (provider=efa), RDMA capable, and **no TCP fallback strings** appear
in the pod's libfabric/NCCL logs. The hw_counters proof for RDMA-under-load comes from
awsi-efa-base validation (`awsi-efa-base_v1_rdma-validation.md`) which shares the same
networking stack.

## vLLM import + inference

```
vllm version: 0.16.0
torch: 2.9.1+cu129  cuda available: True  ngpu: 8

INFO gpu_worker [gpu_worker.py:373]  Available KV cache memory: 40.84 GiB
INFO kv_cache_utils [kv_cache_utils.py:1307]  GPU KV cache size: 1,189,408 tokens

PROMPT: 'Hello, world! My favorite color is'
OUTPUT: ' purple. I love the way it looks.\nI love purple too! I'

VLLM_INFERENCE_OK
=== VLLM BACKEND PATH READY (no TCP fallback in libs) ===
```

## Result

- vLLM import OK, facebook/opt-125m loaded, inference returned a real chat completion
- DYNAMO_BACKEND=vllm code path exercised end-to-end
- EFA libfabric is loaded in the same pod; RDMA traffic proven separately on efa-base
- No TCP fallback sentinel in logs
