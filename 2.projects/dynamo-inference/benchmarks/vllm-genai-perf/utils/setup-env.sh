#!/usr/bin/env bash
# Environment Setup Script
# Sets up required environment variables and validates dependencies
set -euo pipefail

echo "Setting up benchmark environment..."

# Benchmark root directory
BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BENCH_ROOT

# Configuration directories
export CONFIGS_DIR="${BENCH_ROOT}/configs"
export SCRIPTS_DIR="${BENCH_ROOT}/scripts"
export RESULTS_DIR="${BENCH_ROOT}/results"
export REPORTS_DIR="${BENCH_ROOT}/reports"
export LOG_DIR="${BENCH_ROOT}/logs"

# Create directories
mkdir -p "$RESULTS_DIR" "$REPORTS_DIR" "$LOG_DIR"

# Default model configuration
export MODEL="${MODEL:-llama-3.3-70b}"
export MODEL_ID="${MODEL_ID:-meta-llama/Llama-3.3-70B-Instruct}"
export TOKENIZER="${TOKENIZER:-$MODEL_ID}"

# Server configuration
export VLLM_URL="${VLLM_URL:-http://localhost:8080}"
export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-8080}"

# Kubernetes configuration
export NAMESPACE="${NAMESPACE:-default}"
export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-vllm-deployment}"

# Try to find worker pod if in Kubernetes
if command -v kubectl &> /dev/null; then
    WORKER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=vllm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$WORKER_POD" ]; then
        export WORKER_POD
        echo "Found worker pod: $WORKER_POD"
    fi
fi

# Benchmark defaults
export DEFAULT_INPUT_LENGTH=102400
export DEFAULT_OUTPUT_LENGTH=500
export DEFAULT_NUM_PROMPTS=100
export DEFAULT_WARMUP_RUNS=10
export DEFAULT_CONCURRENCY=16

# Docker configuration for GenAI-Perf
export GENAI_PERF_IMAGE="${GENAI_PERF_IMAGE:-nvcr.io/nvidia/tritonserver:24.10-py3-sdk}"

# Check required tools
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo "WARNING: $1 not found in PATH"
        return 1
    fi
    return 0
}

echo "Checking dependencies..."
check_tool docker || echo "  - docker: Required for GenAI-Perf benchmarks"
check_tool kubectl || echo "  - kubectl: Required for Kubernetes deployments"
check_tool jq || echo "  - jq: Required for JSON parsing (optional but recommended)"
check_tool python3 || echo "  - python3: Required for Python scripts"

# Python dependencies check
if command -v python3 &> /dev/null; then
    if ! python3 -c "import yaml" 2>/dev/null; then
        echo "WARNING: Python 'yaml' module not found. Install with: pip install pyyaml"
    fi
    if ! python3 -c "import pandas" 2>/dev/null; then
        echo "INFO: Python 'pandas' module not found. Install for enhanced reporting: pip install pandas"
    fi
fi

# Set Python path to include utils
export PYTHONPATH="${BENCH_ROOT}/utils:${PYTHONPATH:-}"

echo "Environment setup complete!"
echo ""
echo "Key Variables:"
echo "  BENCH_ROOT: $BENCH_ROOT"
echo "  MODEL: $MODEL"
echo "  VLLM_URL: $VLLM_URL"
echo "  NAMESPACE: $NAMESPACE"
[ -n "${WORKER_POD:-}" ] && echo "  WORKER_POD: $WORKER_POD"
echo ""
