#!/usr/bin/env bash
# GenAI-Perf Standard Benchmark Script
# Comprehensive client-side performance testing using NVIDIA GenAI-Perf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$(dirname "$SCRIPT_DIR")"

# Default Configuration
MODEL="${MODEL:-llama-3.3-70b}"
MODEL_ID="${MODEL_ID:-meta-llama/Llama-3.3-70B-Instruct}"
TOKENIZER="${TOKENIZER:-$MODEL_ID}"
VLLM_URL="${VLLM_URL:-http://localhost:8080}"
CONCURRENCY="${CONCURRENCY:-16}"
NUM_PROMPTS="${NUM_PROMPTS:-330}"
WARMUP_REQUESTS="${WARMUP_REQUESTS:-10}"
REQUEST_COUNT="${REQUEST_COUNT:-320}"
INPUT_TOKENS_MEAN="${INPUT_TOKENS_MEAN:-102400}"
INPUT_TOKENS_STDDEV="${INPUT_TOKENS_STDDEV:-0}"
OUTPUT_TOKENS_MEAN="${OUTPUT_TOKENS_MEAN:-500}"
OUTPUT_TOKENS_STDDEV="${OUTPUT_TOKENS_STDDEV:-500}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
RESULT_DIR="${RESULT_DIR:-${BENCH_ROOT}/results/genai-perf}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RELEASE_VERSION="${RELEASE_VERSION:-24.10}"

# Logging
LOG_DIR="${BENCH_ROOT}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/genai-perf-${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model) MODEL="$2"; shift 2 ;;
        --model-id) MODEL_ID="$2"; shift 2 ;;
        --url) VLLM_URL="$2"; shift 2 ;;
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
        --num-prompts) NUM_PROMPTS="$2"; shift 2 ;;
        --input-tokens) INPUT_TOKENS_MEAN="$2"; shift 2 ;;
        --output-tokens) OUTPUT_TOKENS_MEAN="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --model NAME              Model name"
            echo "  --model-id ID             Full model ID"
            echo "  --url URL                 vLLM server URL (default: http://localhost:8080)"
            echo "  --concurrency N           Concurrency level (default: 16)"
            echo "  --num-prompts N           Number of prompts (default: 330)"
            echo "  --input-tokens N          Input tokens mean (default: 102400)"
            echo "  --output-tokens N         Output tokens mean (default: 500)"
            exit 0
            ;;
        *) shift ;;
    esac
done

mkdir -p "$RESULT_DIR"
ARTIFACT_DIR="${RESULT_DIR}/artifacts_${TIMESTAMP}"
EXPORT_DIR="${RESULT_DIR}/exports"
mkdir -p "$ARTIFACT_DIR" "$EXPORT_DIR"

log "========================================"
log "GenAI-Perf Standard Benchmark"
log "========================================"
log "Configuration:"
log "  Model: $MODEL_ID"
log "  Server URL: $VLLM_URL"
log "  Concurrency: $CONCURRENCY"
log "  Num Prompts: $NUM_PROMPTS"
log "  Input Tokens: $INPUT_TOKENS_MEAN ± $INPUT_TOKENS_STDDEV"
log "  Output Tokens: $OUTPUT_TOKENS_MEAN ± $OUTPUT_TOKENS_STDDEV"
log "========================================"

# Check server health
if ! curl -sf "${VLLM_URL}/health" > /dev/null 2>&1; then
    log "WARNING: Server at ${VLLM_URL} not accessible"
fi

PROFILE_EXPORT="${EXPORT_DIR}/${MODEL}_c${CONCURRENCY}_${TIMESTAMP}.json"

log "Starting GenAI-Perf benchmark..."

docker run --rm --net=host \
  -v "${ARTIFACT_DIR}:/workspace/artifacts" \
  -v "${EXPORT_DIR}:/workspace/exports" \
  nvcr.io/nvidia/tritonserver:${RELEASE_VERSION}-py3-sdk \
  genai-perf profile \
    -m "$MODEL_ID" \
    --endpoint-type "$ENDPOINT_TYPE" \
    --url "$VLLM_URL" \
    --num-prompts "$NUM_PROMPTS" \
    --synthetic-input-tokens-mean "$INPUT_TOKENS_MEAN" \
    --synthetic-input-tokens-stddev "$INPUT_TOKENS_STDDEV" \
    --output-tokens-mean "$OUTPUT_TOKENS_MEAN" \
    --output-tokens-stddev "$OUTPUT_TOKENS_STDDEV" \
    --extra-inputs min_tokens:500 \
    --extra-inputs max_tokens:1000 \
    --extra-inputs ignore_eos:true \
    --random-seed 0 \
    --num-dataset-entries "${NUM_PROMPTS}" \
    --request-count "$REQUEST_COUNT" \
    --warmup-request-count "${WARMUP_REQUESTS}" \
    --concurrency "$CONCURRENCY" \
    --tokenizer "$TOKENIZER" \
    --artifact-dir "/workspace/artifacts" \
    --profile-export-file "/workspace/exports/$(basename $PROFILE_EXPORT)" \
    --generate-plots 2>&1 | tee -a "$LOG_FILE"

log "Benchmark completed"
log "Results: $ARTIFACT_DIR"
log "Profile: $PROFILE_EXPORT"

# Display metrics
if command -v jq &> /dev/null && [ -f "$PROFILE_EXPORT" ]; then
    log ""
    log "Key Metrics:"
    jq -r '
        "  TTFT p50: " + (.ttft_p50 | tostring) + " ms",
        "  TTFT p99: " + (.ttft_p99 | tostring) + " ms",
        "  ITL p50: " + (.itl_p50 | tostring) + " ms",
        "  ITL p99: " + (.itl_p99 | tostring) + " ms",
        "  Request Throughput: " + (.request_throughput | tostring) + " req/s",
        "  Token Throughput: " + (.output_token_throughput | tostring) + " tok/s"
    ' "$PROFILE_EXPORT" 2>/dev/null | tee -a "$LOG_FILE"
fi

exit 0
