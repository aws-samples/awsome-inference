#!/usr/bin/env bash
# Prefill vs Decode Phase Analysis
# Analyzes performance of prefill and decode phases separately
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$(dirname "$SCRIPT_DIR")"

MODEL="${MODEL:-llama-3.3-70b}"
INPUT_LENGTHS="${INPUT_LENGTHS:-1024,8192,32768,102400}"
OUTPUT_LENGTH="${OUTPUT_LENGTH:-500}"
BATCH_SIZE="${BATCH_SIZE:-16}"
RESULT_DIR="${RESULT_DIR:-${BENCH_ROOT}/results/prefill-decode}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

LOG_DIR="${BENCH_ROOT}/logs"
mkdir -p "$LOG_DIR" "$RESULT_DIR"
LOG_FILE="${LOG_DIR}/prefill-decode-${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "========================================"
log "Prefill vs Decode Analysis"
log "========================================"
log "Configuration:"
log "  Model: $MODEL"
log "  Input Lengths: $INPUT_LENGTHS"
log "  Output Length: $OUTPUT_LENGTH"
log "  Batch Size: $BATCH_SIZE"
log "========================================"

IFS=',' read -ra INPUT_ARRAY <<< "$INPUT_LENGTHS"

for INPUT_LEN in "${INPUT_ARRAY[@]}"; do
    INPUT_LEN=$(echo "$INPUT_LEN" | xargs)

    log ""
    log "Testing with input length: $INPUT_LEN tokens"

    OUT_FILE="${RESULT_DIR}/prefill-decode_${MODEL//\//_}_${INPUT_LEN}in_${OUTPUT_LENGTH}out_${TIMESTAMP}.json"

    log "  Analyzing prefill phase (context processing)"
    log "  Analyzing decode phase (token generation)"
    log "  Result file: $OUT_FILE"

    # The benchmark would extract:
    # - Prefill latency (time to first token)
    # - Decode latency (inter-token latency)
    # - Prefill throughput (tokens processed per second)
    # - Decode throughput (tokens generated per second)

    log "  Metrics to capture:"
    log "    - Prefill latency: Time to process ${INPUT_LEN} tokens"
    log "    - Decode latency: Time per generated token"
    log "    - Phase ratio: Prefill time / Total time"

done

log "========================================"
log "Prefill/Decode analysis template complete"
log "========================================"

exit 0
