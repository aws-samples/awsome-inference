#!/usr/bin/env bash
# vLLM Throughput Benchmark Script
# Tests maximum throughput with varying batch sizes and sequence lengths
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$(dirname "$SCRIPT_DIR")"
source "${BENCH_ROOT}/utils/setup-env.sh" 2>/dev/null || true

# Default Configuration
MODEL="${MODEL:-llama-3.3-70b}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
BATCH_SIZES="${BATCH_SIZES:-1,2,4,8,16,32}"
INPUT_LENGTH="${INPUT_LENGTH:-102000}"
OUTPUT_LENGTH="${OUTPUT_LENGTH:-100}"
NUM_PROMPTS="${NUM_PROMPTS:-100}"
WARMUP_RUNS="${WARMUP_RUNS:-10}"
RESULT_DIR="${RESULT_DIR:-${BENCH_ROOT}/results/throughput}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Logging
LOG_DIR="${BENCH_ROOT}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/vllm-throughput-${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model) MODEL="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --batch-sizes) BATCH_SIZES="$2"; shift 2 ;;
        --input-length) INPUT_LENGTH="$2"; shift 2 ;;
        --output-length) OUTPUT_LENGTH="$2"; shift 2 ;;
        --num-prompts) NUM_PROMPTS="$2"; shift 2 ;;
        --warmup-runs) WARMUP_RUNS="$2"; shift 2 ;;
        --result-dir) RESULT_DIR="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --model MODEL              Model name (default: llama-3.3-70b)"
            echo "  --host HOST                Server host (default: 0.0.0.0)"
            echo "  --port PORT                Server port (default: 8080)"
            echo "  --batch-sizes SIZES        Comma-separated batch sizes (default: 1,2,4,8,16,32)"
            echo "  --input-length LEN         Input sequence length (default: 102000)"
            echo "  --output-length LEN        Output sequence length (default: 100)"
            echo "  --num-prompts N            Number of prompts (default: 100)"
            echo "  --warmup-runs N            Warmup runs (default: 10)"
            echo "  --result-dir DIR           Results directory"
            echo "  --help                     Show this help message"
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Create results directory
mkdir -p "$RESULT_DIR"

log "========================================"
log "vLLM Throughput Benchmark"
log "========================================"
log "Configuration:"
log "  Model: $MODEL"
log "  Server: ${HOST}:${PORT}"
log "  Batch sizes: $BATCH_SIZES"
log "  Input length: $INPUT_LENGTH tokens"
log "  Output length: $OUTPUT_LENGTH tokens"
log "  Num prompts: $NUM_PROMPTS"
log "  Warmup runs: $WARMUP_RUNS"
log "  Results: $RESULT_DIR"
log "  Log file: $LOG_FILE"
log "========================================"

# Check if running inside pod or need to exec
if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
    log "Running from outside cluster - will exec into worker pod"
    if [ -z "${WORKER_POD:-}" ]; then
        # Try to find worker pod
        NAMESPACE="${NAMESPACE:-default}"
        WORKER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=vllm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -z "$WORKER_POD" ]; then
            error "WORKER_POD not found. Set WORKER_POD environment variable or deploy vLLM first."
        fi
        log "Found worker pod: $WORKER_POD"
    fi
    EXEC_PREFIX="kubectl exec -i $WORKER_POD -n ${NAMESPACE:-default} -- bash -c"
else
    log "Running inside cluster"
    EXEC_PREFIX="bash -c"
fi

# Check if benchmark_serving.py exists
if ! $EXEC_PREFIX "test -f /workspace/benchmarks/benchmark_serving.py" 2>/dev/null; then
    log "WARNING: /workspace/benchmarks/benchmark_serving.py not found in pod"
    log "Attempting to locate vLLM benchmark script..."

    # Try alternative locations
    for script_path in \
        "/app/vllm/benchmarks/benchmark_serving.py" \
        "/usr/local/lib/python3.*/dist-packages/vllm/benchmarks/benchmark_serving.py" \
        "$(python3 -c 'import vllm; print(vllm.__path__[0])')/benchmarks/benchmark_serving.py" 2>/dev/null
    do
        if $EXEC_PREFIX "test -f $script_path" 2>/dev/null; then
            BENCHMARK_SCRIPT="$script_path"
            log "Found benchmark script at: $BENCHMARK_SCRIPT"
            break
        fi
    done

    if [ -z "${BENCHMARK_SCRIPT:-}" ]; then
        error "Cannot find vLLM benchmark_serving.py script"
    fi
else
    BENCHMARK_SCRIPT="/workspace/benchmarks/benchmark_serving.py"
fi

# Warmup run
log ""
log "Running warmup with $WARMUP_RUNS prompts..."
WARMUP_RESULT="${RESULT_DIR}/warmup_${TIMESTAMP}.json"

$EXEC_PREFIX "cd /workspace 2>/dev/null || cd /app 2>/dev/null || cd /; python3 $BENCHMARK_SCRIPT \
  --backend vllm \
  --host '$HOST' \
  --port '$PORT' \
  --model '$MODEL' \
  --trust-remote-code \
  --dataset-name random \
  --random-input-len $INPUT_LENGTH \
  --random-output-len $OUTPUT_LENGTH \
  --ignore-eos \
  --num-prompts $WARMUP_RUNS \
  --no-stream \
  --percentile-metrics ttft,tpot,itl,e2el \
  --metric-percentiles 25,50,99 \
  --save-result \
  --result-filename '$WARMUP_RESULT'" >> "$LOG_FILE" 2>&1 || log "Warmup completed with warnings"

log "Warmup completed"

# Main benchmark loop
log ""
log "Starting throughput benchmark sweep..."
log ""

IFS=',' read -ra BATCH_SIZE_ARRAY <<< "$BATCH_SIZES"
RESULTS_JSON="[]"

for BATCH_SIZE in "${BATCH_SIZE_ARRAY[@]}"; do
    BATCH_SIZE=$(echo "$BATCH_SIZE" | xargs)  # Trim whitespace

    log "----------------------------------------"
    log "Running batch size: $BATCH_SIZE"
    log "----------------------------------------"

    OUT_FILE="${RESULT_DIR}/throughput_${MODEL//\//_}_bs${BATCH_SIZE}_${INPUT_LENGTH}in_${OUTPUT_LENGTH}out_${TIMESTAMP}.json"

    # Run benchmark
    if $EXEC_PREFIX "cd /workspace 2>/dev/null || cd /app 2>/dev/null || cd /; python3 $BENCHMARK_SCRIPT \
      --backend vllm \
      --host '$HOST' \
      --port '$PORT' \
      --model '$MODEL' \
      --trust-remote-code \
      --dataset-name random \
      --random-input-len $INPUT_LENGTH \
      --random-output-len $OUTPUT_LENGTH \
      --ignore-eos \
      --num-prompts $BATCH_SIZE \
      --no-stream \
      --percentile-metrics ttft,tpot,itl,e2el \
      --metric-percentiles 25,50,90,95,99 \
      --save-result \
      --result-filename '$OUT_FILE'" >> "$LOG_FILE" 2>&1; then

        log "Completed batch size $BATCH_SIZE -> $OUT_FILE"

        # Copy result from pod if running externally
        if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
            kubectl cp "${WORKER_POD}:${OUT_FILE}" "$OUT_FILE" -n "${NAMESPACE:-default}" 2>/dev/null || \
                log "WARNING: Could not copy result file from pod"
        fi

        # Extract key metrics if jq available
        if command -v jq &> /dev/null && [ -f "$OUT_FILE" ]; then
            THROUGHPUT=$(jq -r '.request_throughput // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")
            TOKEN_THROUGHPUT=$(jq -r '.output_token_throughput // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")
            TTFT_P50=$(jq -r '.ttft_p50 // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")
            TTFT_P99=$(jq -r '.ttft_p99 // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")

            log "  Request Throughput: $THROUGHPUT req/s"
            log "  Token Throughput: $TOKEN_THROUGHPUT tok/s"
            log "  TTFT p50: $TTFT_P50 ms"
            log "  TTFT p99: $TTFT_P99 ms"
        fi
    else
        log "ERROR: Benchmark failed for batch size $BATCH_SIZE"
    fi

    log ""
done

log "========================================"
log "Throughput Benchmark Completed"
log "========================================"

# Generate summary
SUMMARY_FILE="${RESULT_DIR}/summary_${TIMESTAMP}.txt"
log ""
log "Generating summary..."

{
    echo "vLLM Throughput Benchmark Summary"
    echo "=================================="
    echo "Timestamp: $(date)"
    echo "Model: $MODEL"
    echo "Configuration:"
    echo "  Input Length: $INPUT_LENGTH tokens"
    echo "  Output Length: $OUTPUT_LENGTH tokens"
    echo "  Num Prompts: $NUM_PROMPTS"
    echo ""
    echo "Results by Batch Size:"
    echo "======================"

    if command -v jq &> /dev/null; then
        echo ""
        printf "%-12s | %-20s | %-20s | %-15s | %-15s\n" \
            "Batch Size" "Request Throughput" "Token Throughput" "TTFT p50 (ms)" "TTFT p99 (ms)"
        printf "%-12s-+-%-20s-+-%-20s-+-%-15s-+-%-15s\n" \
            "------------" "--------------------" "--------------------" "---------------" "---------------"

        for BATCH_SIZE in "${BATCH_SIZE_ARRAY[@]}"; do
            BATCH_SIZE=$(echo "$BATCH_SIZE" | xargs)
            RESULT_FILE="${RESULT_DIR}/throughput_${MODEL//\//_}_bs${BATCH_SIZE}_${INPUT_LENGTH}in_${OUTPUT_LENGTH}out_${TIMESTAMP}.json"

            if [ -f "$RESULT_FILE" ]; then
                THROUGHPUT=$(jq -r '.request_throughput // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")
                TOKEN_THROUGHPUT=$(jq -r '.output_token_throughput // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")
                TTFT_P50=$(jq -r '.ttft_p50 // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")
                TTFT_P99=$(jq -r '.ttft_p99 // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")

                printf "%-12s | %-20s | %-20s | %-15s | %-15s\n" \
                    "$BATCH_SIZE" "$THROUGHPUT" "$TOKEN_THROUGHPUT" "$TTFT_P50" "$TTFT_P99"
            else
                printf "%-12s | %-20s | %-20s | %-15s | %-15s\n" \
                    "$BATCH_SIZE" "FAILED" "-" "-" "-"
            fi
        done
    else
        echo "Install jq for detailed metrics"
    fi

    echo ""
    echo "Result Files:"
    echo "============="
    ls -lh "$RESULT_DIR"/*_${TIMESTAMP}.json 2>/dev/null || echo "No results found"

    echo ""
    echo "Log File: $LOG_FILE"

} | tee "$SUMMARY_FILE"

log ""
log "Summary saved to: $SUMMARY_FILE"
log "All results saved to: $RESULT_DIR"
log ""
log "To archive results:"
log "  tar czf throughput-results-${TIMESTAMP}.tar.gz $RESULT_DIR"
log ""

# Return success
exit 0
