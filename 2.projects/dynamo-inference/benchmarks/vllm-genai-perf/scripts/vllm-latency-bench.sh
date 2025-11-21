#!/usr/bin/env bash
# vLLM Latency Benchmark Script
# Measures latency characteristics with different concurrency levels
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$(dirname "$SCRIPT_DIR")"
source "${BENCH_ROOT}/utils/setup-env.sh" 2>/dev/null || true

# Default Configuration
MODEL="${MODEL:-llama-3.3-70b}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
CONCURRENCY="${CONCURRENCY:-1,2,4,8,16,32,64}"
INPUT_LENGTH="${INPUT_LENGTH:-102000}"
OUTPUT_LENGTH="${OUTPUT_LENGTH:-100}"
NUM_PROMPTS="${NUM_PROMPTS:-100}"
WARMUP_RUNS="${WARMUP_RUNS:-10}"
RESULT_DIR="${RESULT_DIR:-${BENCH_ROOT}/results/latency}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Logging
LOG_DIR="${BENCH_ROOT}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/vllm-latency-${TIMESTAMP}.log"

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
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
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
            echo "  --concurrency LEVELS       Comma-separated concurrency levels (default: 1,2,4,8,16,32,64)"
            echo "  --input-length LEN         Input sequence length (default: 102000)"
            echo "  --output-length LEN        Output sequence length (default: 100)"
            echo "  --num-prompts N            Number of prompts per level (default: 100)"
            echo "  --warmup-runs N            Warmup runs (default: 10)"
            echo "  --result-dir DIR           Results directory"
            echo "  --help                     Show this help message"
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

mkdir -p "$RESULT_DIR"

log "========================================"
log "vLLM Latency Benchmark"
log "========================================"
log "Configuration:"
log "  Model: $MODEL"
log "  Server: ${HOST}:${PORT}"
log "  Concurrency levels: $CONCURRENCY"
log "  Input length: $INPUT_LENGTH tokens"
log "  Output length: $OUTPUT_LENGTH tokens"
log "  Num prompts: $NUM_PROMPTS"
log "  Warmup runs: $WARMUP_RUNS"
log "  Results: $RESULT_DIR"
log "========================================"

# Check if running inside pod or need to exec
if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
    if [ -z "${WORKER_POD:-}" ]; then
        NAMESPACE="${NAMESPACE:-default}"
        WORKER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=vllm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -z "$WORKER_POD" ]; then
            error "WORKER_POD not found"
        fi
    fi
    EXEC_PREFIX="kubectl exec -i $WORKER_POD -n ${NAMESPACE:-default} -- bash -c"
else
    EXEC_PREFIX="bash -c"
fi

# Find benchmark script
BENCHMARK_SCRIPT="/workspace/benchmarks/benchmark_serving.py"
if ! $EXEC_PREFIX "test -f $BENCHMARK_SCRIPT" 2>/dev/null; then
    BENCHMARK_SCRIPT="/app/vllm/benchmarks/benchmark_serving.py"
fi

# Warmup
log ""
log "Running warmup..."
WARMUP_RESULT="${RESULT_DIR}/warmup_${TIMESTAMP}.json"

$EXEC_PREFIX "python3 $BENCHMARK_SCRIPT \
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
  --metric-percentiles 25,50,90,95,99 \
  --save-result \
  --result-filename '$WARMUP_RESULT'" >> "$LOG_FILE" 2>&1 || true

log "Warmup completed"
log ""
log "Starting latency benchmark sweep..."
log ""

IFS=',' read -ra CONCURRENCY_ARRAY <<< "$CONCURRENCY"

for CONC in "${CONCURRENCY_ARRAY[@]}"; do
    CONC=$(echo "$CONC" | xargs)

    log "----------------------------------------"
    log "Running concurrency level: $CONC"
    log "----------------------------------------"

    OUT_FILE="${RESULT_DIR}/latency_${MODEL//\//_}_conc${CONC}_${INPUT_LENGTH}in_${OUTPUT_LENGTH}out_${TIMESTAMP}.json"

    if $EXEC_PREFIX "python3 $BENCHMARK_SCRIPT \
      --backend vllm \
      --host '$HOST' \
      --port '$PORT' \
      --model '$MODEL' \
      --trust-remote-code \
      --dataset-name random \
      --random-input-len $INPUT_LENGTH \
      --random-output-len $OUTPUT_LENGTH \
      --ignore-eos \
      --num-prompts $CONC \
      --no-stream \
      --percentile-metrics ttft,tpot,itl,e2el \
      --metric-percentiles 25,50,90,95,99 \
      --save-result \
      --result-filename '$OUT_FILE'" >> "$LOG_FILE" 2>&1; then

        log "Completed concurrency $CONC -> $OUT_FILE"

        if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
            kubectl cp "${WORKER_POD}:${OUT_FILE}" "$OUT_FILE" -n "${NAMESPACE:-default}" 2>/dev/null || true
        fi

        if command -v jq &> /dev/null && [ -f "$OUT_FILE" ]; then
            TTFT_P50=$(jq -r '.ttft_p50 // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")
            TTFT_P99=$(jq -r '.ttft_p99 // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")
            ITL_P50=$(jq -r '.itl_p50 // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")
            ITL_P99=$(jq -r '.itl_p99 // "N/A"' "$OUT_FILE" 2>/dev/null || echo "N/A")

            log "  TTFT p50: $TTFT_P50 ms"
            log "  TTFT p99: $TTFT_P99 ms"
            log "  ITL p50: $ITL_P50 ms"
            log "  ITL p99: $ITL_P99 ms"
        fi
    else
        log "ERROR: Benchmark failed for concurrency $CONC"
    fi

    log ""
done

log "========================================"
log "Latency Benchmark Completed"
log "========================================"

# Generate summary
SUMMARY_FILE="${RESULT_DIR}/summary_${TIMESTAMP}.txt"

{
    echo "vLLM Latency Benchmark Summary"
    echo "==============================="
    echo "Timestamp: $(date)"
    echo "Model: $MODEL"
    echo ""
    echo "Results by Concurrency Level:"
    echo "============================="

    if command -v jq &> /dev/null; then
        echo ""
        printf "%-12s | %-12s | %-12s | %-12s | %-12s\n" \
            "Concurrency" "TTFT p50" "TTFT p99" "ITL p50" "ITL p99"
        printf "%-12s-+-%-12s-+-%-12s-+-%-12s-+-%-12s\n" \
            "------------" "------------" "------------" "------------" "------------"

        for CONC in "${CONCURRENCY_ARRAY[@]}"; do
            CONC=$(echo "$CONC" | xargs)
            RESULT_FILE="${RESULT_DIR}/latency_${MODEL//\//_}_conc${CONC}_${INPUT_LENGTH}in_${OUTPUT_LENGTH}out_${TIMESTAMP}.json"

            if [ -f "$RESULT_FILE" ]; then
                TTFT_P50=$(jq -r '.ttft_p50 // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")
                TTFT_P99=$(jq -r '.ttft_p99 // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")
                ITL_P50=$(jq -r '.itl_p50 // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")
                ITL_P99=$(jq -r '.itl_p99 // "N/A"' "$RESULT_FILE" 2>/dev/null || echo "N/A")

                printf "%-12s | %-12s | %-12s | %-12s | %-12s\n" \
                    "$CONC" "$TTFT_P50" "$TTFT_P99" "$ITL_P50" "$ITL_P99"
            fi
        done
    fi

    echo ""
    echo "Log: $LOG_FILE"

} | tee "$SUMMARY_FILE"

log "Summary saved to: $SUMMARY_FILE"

exit 0
