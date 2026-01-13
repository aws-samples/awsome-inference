To test vLLM on GB200, we will use the instructions in [Expert Parallel Deployment (vLLM)](https://docs.vllm.ai/en/latest/serving/expert_parallel_deployment.html#single-node-deployment).
We will use the image defined [here](https://github.com/pbelevich/vllm-ep/blob/main/vllm-ep.Dockerfile).

## Note
```
EP=TP*DP
```

## Communication Backends for EP
vLLM supports three communication backends for EP:
<img width="764" height="274" alt="image" src="https://github.com/user-attachments/assets/7dc0a088-ce99-4ba0-96ff-1fba39bf6f02" />

## Tests
For this section, we will benchmark:
1. pplx backend on a single node (1 tray)
    1. Model: deepseek-ai/deepseek-moe-16b-base
2. pplx backend on multiple nodes (1 rack)
    1. Model: deepseek-ai/DeepSeek-V3-0324
3. pplx backend on multiple nodes (2 racks)
    1. Model: deepseek-ai/DeepSeek-V3-0324
4. deepep_low_latency  backend on multiple nodes (1 rack)
    1. Model: deepseek-ai/DeepSeek-V3-0324

We will not benchmark with the Expert Parallel load Balancer (EPLB). We will also not test Disaggregated Serving for this run. 


To submit as sbatch, use the `single_node.sbatch` file in the parent directory:
```
# Set HF_TOKEN and HF_HOME as env vars first. Then:
sbatch single_node.sbatch
```

Logs and results will be written to a `logs_single_node` directory  

## Takeaways
1. pplx as a backend doesn't work! This is being worked on it looks like: https://github.com/vllm-project/vllm/issues/24272, https://github.com/perplexityai/pplx-kernels/issues/36
2. deepep also doesn't work! https://github.com/deepseek-ai/DeepEP/issues/392
3. For vLLM -- use the native backend.
4. Also, recommend that you use NCCL, instead of NVSHMEM. There is no reason to use NVSHMEM.
