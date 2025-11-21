# Quick Start Guide

Get started with the vLLM and GenAI-Perf benchmark suite in minutes.

## Installation

### 1. Install Dependencies

```bash
cd /home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks/vllm-genai-perf
./utils/install-deps.sh
```

This installs:
- System tools (jq, curl)
- Python packages (pyyaml, requests, tabulate)
- Optional packages (pandas, matplotlib)
- GenAI-Perf Docker image

### 2. Setup Environment

```bash
source ./utils/setup-env.sh
```

This sets up environment variables and validates your configuration.

## Running Benchmarks

### Option 1: Run All Benchmarks (Recommended for First Run)

```bash
./master-benchmark.sh --all
```

This runs:
- vLLM throughput benchmark
- vLLM latency benchmark
- GenAI-Perf standard benchmark
- GenAI-Perf parameter sweep
- Prefill vs decode analysis
- Token generation benchmark

### Option 2: Run Specific Benchmarks

```bash
# Run only throughput test
./master-benchmark.sh --throughput

# Run throughput and latency
./master-benchmark.sh --throughput --latency

# Run GenAI-Perf tests
./master-benchmark.sh --genai-perf
```

### Option 3: Run Individual Scripts

```bash
# vLLM throughput
./scripts/vllm-throughput-bench.sh

# vLLM latency
./scripts/vllm-latency-bench.sh

# GenAI-Perf
./scripts/genai-perf-standard.sh
```

## Prerequisites

Before running benchmarks, ensure:

1. **vLLM Server is Running**
   ```bash
   # Check server health
   curl http://localhost:8080/health

   # If using Kubernetes with port-forward
   kubectl port-forward svc/vllm-service 8080:8080
   ```

2. **Server URL is Correct**
   ```bash
   # Set server URL
   export VLLM_URL="http://localhost:8080"

   # Or for Kubernetes service
   export VLLM_URL="http://vllm-service.default.svc.cluster.local:8080"
   ```

3. **Model is Configured**
   ```bash
   # Set model name
   export MODEL="llama-3.3-70b"
   export MODEL_ID="meta-llama/Llama-3.3-70B-Instruct"
   ```

## Basic Examples

### Example 1: Quick Throughput Test

```bash
./scripts/vllm-throughput-bench.sh \
  --model llama-3.3-70b \
  --batch-sizes 8,16,32 \
  --input-length 8192 \
  --output-length 500
```

### Example 2: Latency Test with Different Concurrency

```bash
./scripts/vllm-latency-bench.sh \
  --model llama-3.3-70b \
  --concurrency 1,4,16,32 \
  --input-length 8192
```

### Example 3: GenAI-Perf with Custom Parameters

```bash
./scripts/genai-perf-standard.sh \
  --model llama-3.3-70b \
  --concurrency 16 \
  --num-prompts 100 \
  --input-tokens 8192 \
  --output-tokens 500
```

### Example 4: Complete Suite with Custom Model

```bash
./master-benchmark.sh \
  --model llama-70b \
  --model-id meta-llama/Llama-2-70b-hf \
  --url http://localhost:8080 \
  --all
```

## Results

### View Results

All results are saved in timestamped directories:

```bash
# List results
ls -lh results/

# View throughput results
cat results/throughput_*/summary_*.txt

# View latency results
cat results/latency_*/summary_*.txt
```

### Parse Results

```bash
# Parse all results in a directory
./utils/parse-results.py results/throughput_20251120_120000/

# Get summary statistics
./utils/parse-results.py results/ --format summary

# Export to JSON
./utils/parse-results.py results/ --format json --output results.json
```

### Compare Results

```bash
# Compare two benchmark runs
./utils/compare-results.py \
  results/throughput_*/result1.json \
  results/throughput_*/result2.json

# Compare with baseline
./utils/compare-results.py \
  results/*.json \
  --baseline 0 \
  --metrics request_throughput ttft_p99 itl_p50
```

## Troubleshooting

### Server Not Reachable

```bash
# Check if server is running
curl http://localhost:8080/health

# For Kubernetes, ensure port-forward is active
kubectl port-forward svc/vllm-service 8080:8080 &

# Verify with
curl http://localhost:8080/health
```

### vLLM Benchmark Script Not Found

The scripts will automatically search for `benchmark_serving.py` in common locations:
- `/workspace/benchmarks/benchmark_serving.py`
- `/app/vllm/benchmarks/benchmark_serving.py`
- Python site-packages vllm location

If still not found, you can specify the path:
```bash
export BENCHMARK_SCRIPT="/path/to/benchmark_serving.py"
```

### Docker Permission Denied

If you get Docker permission errors:
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login, or run
newgrp docker
```

### GenAI-Perf Image Not Found

Pull the GenAI-Perf image manually:
```bash
docker pull nvcr.io/nvidia/tritonserver:24.10-py3-sdk
```

## Configuration Files

### Model Configuration

Edit `configs/model-configs.yaml` to add or modify model configurations:

```yaml
models:
  my-custom-model:
    model_id: "org/model-name"
    tensor_parallel: 8
    max_model_len: 131072
    gpu_memory_utilization: 0.90
```

### Benchmark Configuration

Edit `configs/benchmark-configs.yaml` to customize benchmark parameters:

```yaml
throughput:
  batch_sizes: [1, 4, 16, 32, 64]
  input_lengths: [128, 1024, 8192, 32768]
  output_lengths: [100, 500, 1000]
```

### GPU Configuration

Edit `configs/gpu-configs.yaml` to configure GPU settings:

```yaml
multi_gpu_8x:
  h100_8x_tp:
    gpu_count: 8
    tensor_parallel: 8
    pipeline_parallel: 1
```

## Next Steps

1. **Review Results**: Check the generated reports in `reports/`
2. **Compare Runs**: Use comparison tools to analyze performance changes
3. **Tune Parameters**: Adjust configurations based on results
4. **Scale Testing**: Test with different model sizes and GPU configurations

## Common Workflows

### Daily Performance Testing

```bash
# Run standard benchmark suite daily
./master-benchmark.sh --throughput --latency --genai-perf

# Archive results
tar czf daily-benchmark-$(date +%Y%m%d).tar.gz results/
```

### Before/After Comparison

```bash
# Run baseline
./master-benchmark.sh --all

# Make changes (upgrade, config change, etc.)

# Run comparison
./master-benchmark.sh --all

# Compare results
./utils/compare-results.py \
  results/before/*.json \
  results/after/*.json
```

### Model Evaluation

```bash
# Test different models
for MODEL in llama-7b llama-13b llama-70b; do
  ./master-benchmark.sh \
    --model $MODEL \
    --throughput --latency
done

# Compare models
./utils/compare-results.py results/*/*.json
```

## Support

For issues or questions:
1. Check logs in `logs/`
2. Review configuration files in `configs/`
3. See main documentation in `README.md`

## Additional Resources

- [Full Documentation](README.md)
- [vLLM Documentation](https://docs.vllm.ai/)
- [GenAI-Perf Guide](https://github.com/triton-inference-server/perf_analyzer/blob/main/genai-perf/README.md)
- [Benchmarking Best Practices](../../BENCHMARKING_GUIDE.md)
