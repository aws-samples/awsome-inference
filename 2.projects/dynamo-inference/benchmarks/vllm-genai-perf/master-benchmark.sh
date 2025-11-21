#!/usr/bin/env bash
# Master Orchestration Script for vLLM and GenAI-Perf Benchmarks
# Runs complete benchmark suite with a single command
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
RESULTS_DIR="${SCRIPT_DIR}/results"
REPORTS_DIR="${SCRIPT_DIR}/reports"
LOG_DIR="${SCRIPT_DIR}/logs"

# Create directories
mkdir -p "$RESULTS_DIR" "$REPORTS_DIR" "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MASTER_LOG="${LOG_DIR}/master-benchmark-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MASTER_LOG"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*${NC}" | tee -a "$MASTER_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $*${NC}" | tee -a "$MASTER_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}" | tee -a "$MASTER_LOG"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ $*${NC}" | tee -a "$MASTER_LOG"
}

# Default configuration
MODEL="${MODEL:-llama-3.3-70b}"
MODEL_ID="${MODEL_ID:-meta-llama/Llama-3.3-70B-Instruct}"
VLLM_URL="${VLLM_URL:-http://localhost:8080}"
RUN_ALL=false
RUN_VLLM_THROUGHPUT=false
RUN_VLLM_LATENCY=false
RUN_GENAI_PERF=false
RUN_GENAI_PERF_SWEEP=false
RUN_MULTI_GPU=false
RUN_TENSOR_PARALLEL=false
RUN_PIPELINE_PARALLEL=false
RUN_QUANTIZATION=false
RUN_PREFILL_DECODE=false
RUN_TOKEN_GENERATION=false
SKIP_SETUP=false
CLEANUP_AFTER=true
GENERATE_REPORT=true

print_banner() {
    log ""
    log "════════════════════════════════════════════════════════════════"
    log "     vLLM & GenAI-Perf Comprehensive Benchmark Suite"
    log "════════════════════════════════════════════════════════════════"
    log ""
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Master orchestration script for running vLLM and GenAI-Perf benchmarks.

OPTIONS:
    --all                       Run all benchmarks
    --throughput               Run vLLM throughput benchmark
    --latency                  Run vLLM latency benchmark
    --genai-perf               Run GenAI-Perf standard benchmark
    --genai-perf-sweep         Run GenAI-Perf parameter sweep
    --multi-gpu                Run multi-GPU scaling benchmark
    --tensor-parallel          Run tensor parallelism benchmark
    --pipeline-parallel        Run pipeline parallelism benchmark
    --quantization             Run quantization comparison benchmark
    --prefill-decode           Run prefill vs decode analysis
    --token-generation         Run token generation benchmark

CONFIGURATION:
    --model NAME               Model name (default: llama-3.3-70b)
    --model-id ID              Full model ID (default: meta-llama/Llama-3.3-70B-Instruct)
    --url URL                  vLLM server URL (default: http://localhost:8080)
    --skip-setup               Skip environment setup
    --no-cleanup               Don't cleanup after benchmarks
    --no-report                Don't generate final report

EXAMPLES:
    # Run all benchmarks
    $0 --all

    # Run specific benchmarks
    $0 --throughput --latency --genai-perf

    # Run with custom model
    $0 --model llama-70b --model-id meta-llama/Llama-2-70b-hf --all

    # Run against specific server
    $0 --url http://vllm-service:8080 --throughput

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            RUN_ALL=true
            shift
            ;;
        --throughput)
            RUN_VLLM_THROUGHPUT=true
            shift
            ;;
        --latency)
            RUN_VLLM_LATENCY=true
            shift
            ;;
        --genai-perf)
            RUN_GENAI_PERF=true
            shift
            ;;
        --genai-perf-sweep)
            RUN_GENAI_PERF_SWEEP=true
            shift
            ;;
        --multi-gpu)
            RUN_MULTI_GPU=true
            shift
            ;;
        --tensor-parallel)
            RUN_TENSOR_PARALLEL=true
            shift
            ;;
        --pipeline-parallel)
            RUN_PIPELINE_PARALLEL=true
            shift
            ;;
        --quantization)
            RUN_QUANTIZATION=true
            shift
            ;;
        --prefill-decode)
            RUN_PREFILL_DECODE=true
            shift
            ;;
        --token-generation)
            RUN_TOKEN_GENERATION=true
            shift
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --model-id)
            MODEL_ID="$2"
            shift 2
            ;;
        --url)
            VLLM_URL="$2"
            shift 2
            ;;
        --skip-setup)
            SKIP_SETUP=true
            shift
            ;;
        --no-cleanup)
            CLEANUP_AFTER=false
            shift
            ;;
        --no-report)
            GENERATE_REPORT=false
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# If --all is specified, enable all benchmarks
if [ "$RUN_ALL" = true ]; then
    RUN_VLLM_THROUGHPUT=true
    RUN_VLLM_LATENCY=true
    RUN_GENAI_PERF=true
    RUN_GENAI_PERF_SWEEP=true
    RUN_MULTI_GPU=false  # Requires special setup
    RUN_TENSOR_PARALLEL=false  # Requires special setup
    RUN_PIPELINE_PARALLEL=false  # Requires special setup
    RUN_QUANTIZATION=false  # Requires different model variants
    RUN_PREFILL_DECODE=true
    RUN_TOKEN_GENERATION=true
fi

# Check if any benchmark is selected
if [ "$RUN_VLLM_THROUGHPUT" = false ] && \
   [ "$RUN_VLLM_LATENCY" = false ] && \
   [ "$RUN_GENAI_PERF" = false ] && \
   [ "$RUN_GENAI_PERF_SWEEP" = false ] && \
   [ "$RUN_MULTI_GPU" = false ] && \
   [ "$RUN_TENSOR_PARALLEL" = false ] && \
   [ "$RUN_PIPELINE_PARALLEL" = false ] && \
   [ "$RUN_QUANTIZATION" = false ] && \
   [ "$RUN_PREFILL_DECODE" = false ] && \
   [ "$RUN_TOKEN_GENERATION" = false ]; then
    log_error "No benchmark selected. Use --all or specify individual benchmarks."
    print_usage
    exit 1
fi

print_banner

log_info "Configuration:"
log_info "  Model: $MODEL"
log_info "  Model ID: $MODEL_ID"
log_info "  Server URL: $VLLM_URL"
log_info "  Results Directory: $RESULTS_DIR"
log_info "  Log File: $MASTER_LOG"
log ""

# Environment setup
if [ "$SKIP_SETUP" = false ]; then
    log_info "Setting up environment..."
    if [ -f "${SCRIPT_DIR}/utils/setup-env.sh" ]; then
        source "${SCRIPT_DIR}/utils/setup-env.sh"
        log_success "Environment setup complete"
    else
        log_warning "setup-env.sh not found, skipping environment setup"
    fi
    log ""
fi

# Check server connectivity
log_info "Checking vLLM server connectivity..."
if curl -sf "${VLLM_URL}/health" > /dev/null 2>&1; then
    log_success "Server is reachable at $VLLM_URL"
else
    log_warning "Server at $VLLM_URL is not reachable. Benchmarks may fail."
    log_warning "Make sure vLLM server is running and accessible."
fi
log ""

# Track benchmark results
BENCHMARK_RESULTS=()
FAILED_BENCHMARKS=()

run_benchmark() {
    local name="$1"
    local script="$2"
    shift 2
    local args=("$@")

    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Running: $name"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    START_TIME=$(date +%s)

    if [ -f "$script" ]; then
        if bash "$script" "${args[@]}" 2>&1 | tee -a "$MASTER_LOG"; then
            END_TIME=$(date +%s)
            DURATION=$((END_TIME - START_TIME))
            log_success "$name completed in ${DURATION}s"
            BENCHMARK_RESULTS+=("✓ $name (${DURATION}s)")
            return 0
        else
            END_TIME=$(date +%s)
            DURATION=$((END_TIME - START_TIME))
            log_error "$name failed after ${DURATION}s"
            FAILED_BENCHMARKS+=("✗ $name (${DURATION}s)")
            return 1
        fi
    else
        log_error "Script not found: $script"
        FAILED_BENCHMARKS+=("✗ $name (script not found)")
        return 1
    fi
}

# Run benchmarks
TOTAL_START_TIME=$(date +%s)

if [ "$RUN_VLLM_THROUGHPUT" = true ]; then
    run_benchmark "vLLM Throughput Benchmark" \
        "${SCRIPTS_DIR}/vllm-throughput-bench.sh" \
        --model "$MODEL" \
        --result-dir "${RESULTS_DIR}/throughput_${TIMESTAMP}" || true
fi

if [ "$RUN_VLLM_LATENCY" = true ]; then
    run_benchmark "vLLM Latency Benchmark" \
        "${SCRIPTS_DIR}/vllm-latency-bench.sh" \
        --model "$MODEL" \
        --result-dir "${RESULTS_DIR}/latency_${TIMESTAMP}" || true
fi

if [ "$RUN_GENAI_PERF" = true ]; then
    run_benchmark "GenAI-Perf Standard Benchmark" \
        "${SCRIPTS_DIR}/genai-perf-standard.sh" \
        --model "$MODEL" \
        --model-id "$MODEL_ID" \
        --url "$VLLM_URL" \
        --result-dir "${RESULTS_DIR}/genai-perf_${TIMESTAMP}" || true
fi

if [ "$RUN_GENAI_PERF_SWEEP" = true ]; then
    if [ -f "${SCRIPTS_DIR}/genai-perf-sweep.sh" ]; then
        run_benchmark "GenAI-Perf Parameter Sweep" \
            "${SCRIPTS_DIR}/genai-perf-sweep.sh" \
            --model "$MODEL" \
            --model-id "$MODEL_ID" \
            --url "$VLLM_URL" \
            --result-dir "${RESULTS_DIR}/genai-perf-sweep_${TIMESTAMP}" || true
    else
        log_warning "genai-perf-sweep.sh not found, skipping"
    fi
fi

if [ "$RUN_MULTI_GPU" = true ]; then
    if [ -f "${SCRIPTS_DIR}/multi-gpu-bench.sh" ]; then
        run_benchmark "Multi-GPU Benchmark" \
            "${SCRIPTS_DIR}/multi-gpu-bench.sh" \
            --model "$MODEL" \
            --result-dir "${RESULTS_DIR}/multi-gpu_${TIMESTAMP}" || true
    else
        log_warning "multi-gpu-bench.sh not found, skipping"
    fi
fi

if [ "$RUN_TENSOR_PARALLEL" = true ]; then
    if [ -f "${SCRIPTS_DIR}/tensor-parallel-bench.sh" ]; then
        run_benchmark "Tensor Parallel Benchmark" \
            "${SCRIPTS_DIR}/tensor-parallel-bench.sh" \
            --model "$MODEL" \
            --result-dir "${RESULTS_DIR}/tensor-parallel_${TIMESTAMP}" || true
    else
        log_warning "tensor-parallel-bench.sh not found, skipping"
    fi
fi

if [ "$RUN_PIPELINE_PARALLEL" = true ]; then
    if [ -f "${SCRIPTS_DIR}/pipeline-parallel-bench.sh" ]; then
        run_benchmark "Pipeline Parallel Benchmark" \
            "${SCRIPTS_DIR}/pipeline-parallel-bench.sh" \
            --model "$MODEL" \
            --result-dir "${RESULTS_DIR}/pipeline-parallel_${TIMESTAMP}" || true
    else
        log_warning "pipeline-parallel-bench.sh not found, skipping"
    fi
fi

if [ "$RUN_QUANTIZATION" = true ]; then
    if [ -f "${SCRIPTS_DIR}/quantization-bench.sh" ]; then
        run_benchmark "Quantization Benchmark" \
            "${SCRIPTS_DIR}/quantization-bench.sh" \
            --model "$MODEL" \
            --result-dir "${RESULTS_DIR}/quantization_${TIMESTAMP}" || true
    else
        log_warning "quantization-bench.sh not found, skipping"
    fi
fi

if [ "$RUN_PREFILL_DECODE" = true ]; then
    if [ -f "${SCRIPTS_DIR}/prefill-decode-bench.sh" ]; then
        run_benchmark "Prefill vs Decode Benchmark" \
            "${SCRIPTS_DIR}/prefill-decode-bench.sh" \
            --model "$MODEL" \
            --result-dir "${RESULTS_DIR}/prefill-decode_${TIMESTAMP}" || true
    else
        log_warning "prefill-decode-bench.sh not found, skipping"
    fi
fi

if [ "$RUN_TOKEN_GENERATION" = true ]; then
    if [ -f "${SCRIPTS_DIR}/token-generation-bench.sh" ]; then
        run_benchmark "Token Generation Benchmark" \
            "${SCRIPTS_DIR}/token-generation-bench.sh" \
            --model "$MODEL" \
            --result-dir "${RESULTS_DIR}/token-generation_${TIMESTAMP}" || true
    else
        log_warning "token-generation-bench.sh not found, skipping"
    fi
fi

TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$((TOTAL_END_TIME - TOTAL_START_TIME))

# Generate final summary
log ""
log "════════════════════════════════════════════════════════════════"
log "     Benchmark Suite Completed"
log "════════════════════════════════════════════════════════════════"
log ""
log "Total Duration: ${TOTAL_DURATION}s"
log ""
log "Completed Benchmarks:"
for result in "${BENCHMARK_RESULTS[@]}"; do
    log_success "$result"
done

if [ ${#FAILED_BENCHMARKS[@]} -gt 0 ]; then
    log ""
    log "Failed Benchmarks:"
    for failed in "${FAILED_BENCHMARKS[@]}"; do
        log_error "$failed"
    done
fi

log ""
log "Results Directory: $RESULTS_DIR"
log "Master Log: $MASTER_LOG"
log ""

# Generate report
if [ "$GENERATE_REPORT" = true ]; then
    log_info "Generating benchmark report..."
    REPORT_FILE="${REPORTS_DIR}/benchmark-report-${TIMESTAMP}.html"

    if [ -f "${SCRIPT_DIR}/utils/generate-report.py" ]; then
        python3 "${SCRIPT_DIR}/utils/generate-report.py" \
            --results-dir "${RESULTS_DIR}" \
            --output "$REPORT_FILE" \
            --timestamp "$TIMESTAMP" 2>&1 | tee -a "$MASTER_LOG" || \
            log_warning "Report generation failed"

        if [ -f "$REPORT_FILE" ]; then
            log_success "Report generated: $REPORT_FILE"
        fi
    else
        log_warning "generate-report.py not found, skipping report generation"
    fi
fi

# Cleanup
if [ "$CLEANUP_AFTER" = true ]; then
    log_info "Cleaning up temporary files..."
    # Add cleanup logic here if needed
    log_success "Cleanup complete"
fi

log ""
log "════════════════════════════════════════════════════════════════"
log_success "All operations completed!"
log "════════════════════════════════════════════════════════════════"
log ""

# Exit with error if any benchmark failed
if [ ${#FAILED_BENCHMARKS[@]} -gt 0 ]; then
    exit 1
else
    exit 0
fi
