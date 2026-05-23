# Round 7 — Dynamo config matrix on rev8 image

**Image:** `${ECR_REGISTRY}/dynamo-efa:520cfc584abb`
**Cluster:** P5.48xlarge HyperPod (2 nodes)

| Config | Backend | Features | Pods Ready | /v1/models | /v1/completions | Time |
|---|---|---|---|---|---|---|
| vllm-agg-router | vLLM | vLLM aggregated + KV router | 0/3 | POD-NOT-READY | N/A (N/A) | 770s |
| vllm-disagg-router | vLLM | vLLM disaggregated + KV router (cross-node) | 0/3 | POD-NOT-READY | N/A (N/A) | 776s |
| vllm-disagg-kvbm | vLLM | vLLM disaggregated + KVBM multi-tier cache | 0/3 | POD-NOT-READY | N/A (N/A) | 775s |
