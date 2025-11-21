# vLLM and GenAI-Perf Comprehensive Benchmark Suite

This directory contains a comprehensive benchmark suite for testing vLLM inference performance using both native vLLM benchmarks and NVIDIA GenAI-Perf tools.

## Overview

This benchmark suite provides:
- **vLLM Native Benchmarks**: Throughput and latency testing with various configurations
- **GenAI-Perf Benchmarks**: Comprehensive LLM performance analysis
- **Multi-GPU Testing**: Single GPU, multi-GPU, tensor parallel, and pipeline parallel configurations
- **Quantization Testing**: FP16, INT8, INT4, and other quantization levels
- **Performance Analysis**: Prefill vs decode performance, token generation benchmarks
- **Automated Reporting**: Result collection, comparison, and visualization

## Directory Structure

```
vllm-genai-perf/
├── README.md                          # This file
├── master-benchmark.sh                # Master orchestration script
├── scripts/                           # Individual benchmark scripts
│   ├── vllm-throughput-bench.sh      # vLLM throughput testing
│   ├── vllm-latency-bench.sh         # vLLM latency testing
│   ├── genai-perf-standard.sh        # GenAI-Perf standard benchmark
│   ├── genai-perf-sweep.sh           # GenAI-Perf parameter sweep
│   ├── multi-gpu-bench.sh            # Multi-GPU testing
│   ├── tensor-parallel-bench.sh      # Tensor parallel configurations
│   ├── pipeline-parallel-bench.sh    # Pipeline parallel configurations
│   ├── quantization-bench.sh         # Quantization testing
│   ├── prefill-decode-bench.sh       # Prefill vs decode analysis
│   └── token-generation-bench.sh     # Token generation benchmarks
├── configs/                           # Configuration files
│   ├── model-configs.yaml            # Model configurations (7B, 13B, 70B)
│   ├── benchmark-configs.yaml        # Benchmark parameters
│   └── gpu-configs.yaml              # GPU and parallelism settings
├── utils/                            # Utility scripts
│   ├── setup-env.sh                  # Environment setup
│   ├── install-deps.sh               # Install dependencies
│   ├── parse-results.py              # Results parser
│   ├── compare-results.py            # Results comparison
│   └── generate-report.py            # Report generation
├── results/                          # Benchmark results (gitignored)
└── reports/                          # Generated reports (gitignored)
```

## Quick Start

### Prerequisites

1. Kubernetes cluster with GPU nodes
2. NVIDIA GPU Operator installed
3. Docker installed (for GenAI-Perf)
4. kubectl configured
5. Hugging Face token (for gated models)

### Installation

```bash
# Install dependencies
cd /home/ubuntu/awsome-inference/2.projects/dynamo-inference/benchmarks/vllm-genai-perf
./utils/install-deps.sh

# Setup environment
./utils/setup-env.sh
```

### Running Benchmarks

#### Run All Benchmarks
```bash
# Run complete benchmark suite
./master-benchmark.sh --all

# Run with specific model
./master-benchmark.sh --model llama-3.3-70b --all

# Run specific benchmark type
./master-benchmark.sh --benchmark throughput
```

#### Run Individual Benchmarks
```bash
# vLLM throughput
./scripts/vllm-throughput-bench.sh --model llama-3.3-70b

# GenAI-Perf standard
./scripts/genai-perf-standard.sh --concurrency 16

# Multi-GPU testing
./scripts/multi-gpu-bench.sh --gpus 8 --tensor-parallel 8

# Quantization testing
./scripts/quantization-bench.sh --quantization fp16,int8,int4
```

## Benchmark Types

### 1. vLLM Throughput Benchmark
Tests maximum throughput with varying batch sizes and sequence lengths.

**Metrics:**
- Requests per second
- Tokens per second
- GPU utilization
- Memory usage

**Usage:**
```bash
./scripts/vllm-throughput-bench.sh \
  --model llama-3.3-70b \
  --batch-sizes 1,2,4,8,16,32 \
  --input-length 102400 \
  --output-length 500
```

### 2. vLLM Latency Benchmark
Measures latency characteristics with different concurrency levels.

**Metrics:**
- Time to First Token (TTFT)
- Inter-Token Latency (ITL)
- End-to-End Latency
- Percentiles (p50, p90, p95, p99)

**Usage:**
```bash
./scripts/vllm-latency-bench.sh \
  --model llama-3.3-70b \
  --concurrency 1,2,4,8,16,32,64 \
  --num-prompts 100
```

### 3. GenAI-Perf Standard Benchmark
Comprehensive client-side performance testing using NVIDIA GenAI-Perf.

**Metrics:**
- TTFT (p50, p90, p99)
- ITL (p50, p90, p99)
- Request throughput
- Output token throughput
- GPU utilization

**Usage:**
```bash
./scripts/genai-perf-standard.sh \
  --model llama-3.3-70b \
  --concurrency 16 \
  --num-prompts 330 \
  --input-tokens 102400
```

### 4. Multi-GPU Benchmark
Tests performance scaling across multiple GPUs.

**Configurations:**
- Single GPU (baseline)
- 2 GPUs
- 4 GPUs
- 8 GPUs

**Usage:**
```bash
./scripts/multi-gpu-bench.sh \
  --model llama-3.3-70b \
  --gpu-counts 1,2,4,8
```

### 5. Tensor Parallel Benchmark
Tests tensor parallelism configurations for model sharding.

**Configurations:**
- TP=1 (no parallelism)
- TP=2
- TP=4
- TP=8

**Usage:**
```bash
./scripts/tensor-parallel-bench.sh \
  --model llama-3.3-70b \
  --tensor-parallel 1,2,4,8
```

### 6. Pipeline Parallel Benchmark
Tests pipeline parallelism for large model inference.

**Configurations:**
- PP=1 (no parallelism)
- PP=2
- PP=4
- Combined TP+PP

**Usage:**
```bash
./scripts/pipeline-parallel-bench.sh \
  --model llama-3.3-70b \
  --pipeline-parallel 1,2,4
```

### 7. Quantization Benchmark
Compares performance across different quantization levels.

**Quantization Levels:**
- FP16 (baseline)
- INT8
- INT4
- FP8 (H100)
- AWQ
- GPTQ

**Usage:**
```bash
./scripts/quantization-bench.sh \
  --model llama-3.3-70b \
  --quantization fp16,int8,int4,fp8
```

### 8. Prefill vs Decode Benchmark
Analyzes prefill and decode phase performance separately.

**Metrics:**
- Prefill latency
- Decode latency
- Prefill throughput
- Decode throughput
- Phase breakdown

**Usage:**
```bash
./scripts/prefill-decode-bench.sh \
  --model llama-3.3-70b \
  --input-lengths 1024,8192,32768,102400
```

### 9. Token Generation Benchmark
Measures token generation performance with various settings.

**Tests:**
- Fixed output length
- Variable output length
- Streaming vs batch
- Temperature variations

**Usage:**
```bash
./scripts/token-generation-bench.sh \
  --model llama-3.3-70b \
  --output-lengths 100,500,1000,2000
```

## Configuration Files

### model-configs.yaml
Defines model configurations for different sizes:
```yaml
models:
  llama-7b:
    model_id: "meta-llama/Llama-2-7b-hf"
    tensor_parallel: 1
    max_model_len: 4096
  llama-13b:
    model_id: "meta-llama/Llama-2-13b-hf"
    tensor_parallel: 2
    max_model_len: 4096
  llama-70b:
    model_id: "meta-llama/Llama-3.3-70B-Instruct"
    tensor_parallel: 8
    max_model_len: 131072
```

### benchmark-configs.yaml
Benchmark parameters:
```yaml
throughput:
  batch_sizes: [1, 2, 4, 8, 16, 32, 64]
  input_length: 102400
  output_length: 500
  num_prompts: 100

latency:
  concurrency: [1, 2, 4, 8, 16, 32, 64]
  num_prompts: 100
  percentiles: [50, 90, 95, 99]

genai_perf:
  concurrency: 16
  num_prompts: 330
  warmup_requests: 10
  input_tokens_mean: 102400
  output_tokens_mean: 500
```

### gpu-configs.yaml
GPU and parallelism settings:
```yaml
single_gpu:
  gpu_count: 1
  tensor_parallel: 1
  pipeline_parallel: 1

multi_gpu_8x:
  gpu_count: 8
  tensor_parallel: 8
  pipeline_parallel: 1

multi_gpu_16x_tp:
  gpu_count: 16
  tensor_parallel: 16
  pipeline_parallel: 1

multi_gpu_16x_pp:
  gpu_count: 16
  tensor_parallel: 8
  pipeline_parallel: 2
```

## Results and Reports

### Results Format
All benchmarks generate JSON results with standardized format:
```json
{
  "benchmark": "vllm-throughput",
  "timestamp": "2025-11-20T12:00:00Z",
  "model": "llama-3.3-70b",
  "configuration": {
    "batch_size": 16,
    "input_length": 102400,
    "output_length": 500
  },
  "metrics": {
    "throughput_rps": 25.3,
    "throughput_tps": 12650,
    "ttft_p99": 1450,
    "itl_p50": 45,
    "gpu_utilization": 0.92
  }
}
```

### Generate Reports
```bash
# Generate comparison report
./utils/compare-results.py \
  --results results/2025-11-20/ \
  --output reports/comparison-2025-11-20.html

# Generate summary report
./utils/generate-report.py \
  --results results/2025-11-20/ \
  --format html,pdf,csv
```

## Best Practices

### 1. Warmup Runs
Always run warmup iterations before collecting metrics:
```bash
./scripts/vllm-throughput-bench.sh --warmup-runs 5
```

### 2. Multiple Iterations
Run benchmarks multiple times for statistical significance:
```bash
./master-benchmark.sh --iterations 3
```

### 3. Resource Monitoring
Monitor GPU utilization, memory, and network during benchmarks:
```bash
# In separate terminal
watch -n 1 'kubectl exec $POD -- nvidia-smi'
```

### 4. Result Archiving
Archive results with timestamps:
```bash
tar czf benchmark-results-$(date +%Y%m%d-%H%M%S).tar.gz results/
```

## Troubleshooting

### Common Issues

**vLLM not installed:**
```bash
pip install vllm
# or
./utils/install-deps.sh
```

**GenAI-Perf container not found:**
```bash
docker pull nvcr.io/nvidia/tritonserver:24.10-py3-sdk
```

**Out of memory errors:**
- Reduce batch size
- Lower GPU memory utilization
- Enable KV cache quantization (fp8)

**Low throughput:**
- Check GPU utilization
- Verify tensor parallel configuration
- Enable prefix caching
- Adjust max_num_seqs

**Connection refused:**
- Verify port forwarding: `kubectl port-forward svc/vllm 8080:8080`
- Check service status: `kubectl get svc`

## Performance Targets

### H100 (8x GPUs)
| Model | Metric | Target |
|-------|--------|--------|
| Llama 70B | TTFT p99 | < 1500ms |
| Llama 70B | ITL p50 | < 50ms |
| Llama 70B | Throughput | > 20 RPS @ 16 concurrency |
| Llama 70B | GPU Util | > 85% |

### A100 (8x GPUs)
| Model | Metric | Target |
|-------|--------|--------|
| Llama 70B | TTFT p99 | < 2500ms |
| Llama 70B | ITL p50 | < 80ms |
| Llama 70B | Throughput | > 12 RPS @ 16 concurrency |
| Llama 70B | GPU Util | > 80% |

### A10G (Single GPU)
| Model | Metric | Target |
|-------|--------|--------|
| Llama 7B | TTFT p99 | < 500ms |
| Llama 7B | ITL p50 | < 30ms |
| Llama 7B | Throughput | > 15 RPS @ 8 concurrency |
| Llama 7B | GPU Util | > 75% |

## Advanced Usage

### Custom Model Testing
```bash
./master-benchmark.sh \
  --model-id "your-org/your-model" \
  --tensor-parallel 4 \
  --max-model-len 8192
```

### Kubernetes Deployment Testing
```bash
# Test against existing deployment
export VLLM_URL="http://vllm-service.default.svc.cluster.local:8080"
./master-benchmark.sh --all
```

### Disaggregated Mode Testing
```bash
# Test prefill/decode disaggregation
./scripts/prefill-decode-bench.sh \
  --disaggregated \
  --prefill-gpus 2 \
  --decode-gpus 6
```

## References

- [vLLM Documentation](https://docs.vllm.ai/)
- [GenAI-Perf Documentation](https://github.com/triton-inference-server/perf_analyzer/blob/main/genai-perf/README.md)
- [NVIDIA Triton Server](https://github.com/triton-inference-server/server)
- [vLLM Benchmarking Guide](../../BENCHMARKING_GUIDE.md)

## Support

For issues or questions:
1. Check existing benchmark results in `results/`
2. Review logs in `logs/`
3. See main project documentation at `/home/ubuntu/awsome-inference/2.projects/dynamo-inference/`

## License

See main project LICENSE file.
