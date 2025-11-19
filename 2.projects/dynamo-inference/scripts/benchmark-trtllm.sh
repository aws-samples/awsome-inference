#!/bin/bash

# TRT-LLM Benchmark Script
# Tests TRT-LLM deployment performance with various workloads

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/benchmark-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/trtllm_benchmark_${TIMESTAMP}.md"

# Ensure results directory exists
mkdir -p "${RESULTS_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prereqs() {
    print_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Please install jq."
        exit 1
    fi

    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl not found. Please install curl."
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Source environment
NAMESPACE="${NAMESPACE:-dynamo-cloud}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-trtllm-disagg-qwen-full}"
MODEL_ID="${MODEL_ID:-Qwen/Qwen2.5-0.5B-Instruct}"
LOCAL_PORT="${LOCAL_PORT:-8000}"
BASE_URL="http://localhost:${LOCAL_PORT}"

# Test prompts of varying lengths
SHORT_PROMPT="Hello, how are you?"
MEDIUM_PROMPT="Write a detailed explanation of how neural networks work, including the concepts of forward propagation, backpropagation, and gradient descent."
LONG_PROMPT="Explain the history of artificial intelligence from its inception in the 1950s to modern deep learning, covering key milestones like the perceptron, expert systems, neural network winter, the ImageNet moment, and the transformer architecture. Discuss how each advancement built upon previous work and the societal impact of AI development."

# Initialize markdown report
init_report() {
    cat > "$RESULTS_FILE" <<EOF
# TRT-LLM Benchmark Results

**Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Deployment**: ${DEPLOYMENT_NAME}
**Namespace**: ${NAMESPACE}
**Model**: ${MODEL_ID}

---

## System Configuration

EOF

    # Get pod information
    kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${DEPLOYMENT_NAME} -o wide >> "$RESULTS_FILE"

    cat >> "$RESULTS_FILE" <<EOF

---

## Benchmark Results

EOF
}

# Function to test single completion
test_completion() {
    local prompt="$1"
    local max_tokens="$2"
    local test_name="$3"

    print_info "Running test: ${test_name}"

    local start_time=$(date +%s.%N)

    local response=$(curl -s -X POST ${BASE_URL}/v1/completions \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${MODEL_ID}\",
        \"prompt\": \"$prompt\",
        \"max_tokens\": $max_tokens,
        \"temperature\": 0.7
      }" 2>&1)

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    # Parse response
    if echo "$response" | jq -e '.choices[0].text' > /dev/null 2>&1; then
        local text=$(echo "$response" | jq -r '.choices[0].text')
        local tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
        local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
        local total_tokens=$(echo "$response" | jq -r '.usage.total_tokens // 0')

        local tokens_per_sec=$(echo "scale=2; $tokens / $duration" | bc)

        print_success "Test completed in ${duration}s"
        print_info "  Prompt tokens: $prompt_tokens"
        print_info "  Completion tokens: $tokens"
        print_info "  Throughput: ${tokens_per_sec} tokens/sec"

        # Append to report
        cat >> "$RESULTS_FILE" <<EOF
### ${test_name}

- **Duration**: ${duration}s
- **Prompt Tokens**: ${prompt_tokens}
- **Completion Tokens**: ${tokens}
- **Total Tokens**: ${total_tokens}
- **Throughput**: ${tokens_per_sec} tokens/sec
- **Max Tokens Requested**: ${max_tokens}

**Sample Output** (first 200 chars):
\`\`\`
$(echo "$text" | head -c 200)...
\`\`\`

EOF
        return 0
    else
        print_error "Request failed"
        echo "$response"
        return 1
    fi
}

# Function to run latency test (multiple iterations)
latency_test() {
    local prompt="$1"
    local max_tokens="$2"
    local iterations="${3:-5}"
    local test_name="$4"

    print_info "Running latency test: ${test_name} (${iterations} iterations)"

    local total_duration=0
    local successful_requests=0
    local failed_requests=0

    for i in $(seq 1 $iterations); do
        print_info "  Iteration $i/$iterations"

        local start_time=$(date +%s.%N)

        local response=$(curl -s -X POST ${BASE_URL}/v1/completions \
          -H "Content-Type: application/json" \
          -d "{
            \"model\": \"${MODEL_ID}\",
            \"prompt\": \"$prompt\",
            \"max_tokens\": $max_tokens,
            \"temperature\": 0.7
          }" 2>&1)

        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)

        if echo "$response" | jq -e '.choices[0].text' > /dev/null 2>&1; then
            total_duration=$(echo "$total_duration + $duration" | bc)
            successful_requests=$((successful_requests + 1))
        else
            failed_requests=$((failed_requests + 1))
            print_warning "  Request failed"
        fi

        # Brief sleep between requests
        sleep 0.5
    done

    local avg_latency=$(echo "scale=3; $total_duration / $successful_requests" | bc)

    print_success "Latency test completed"
    print_info "  Successful: $successful_requests"
    print_info "  Failed: $failed_requests"
    print_info "  Average latency: ${avg_latency}s"

    # Append to report
    cat >> "$RESULTS_FILE" <<EOF
### ${test_name}

- **Iterations**: ${iterations}
- **Successful Requests**: ${successful_requests}
- **Failed Requests**: ${failed_requests}
- **Average Latency**: ${avg_latency}s
- **Total Duration**: ${total_duration}s

EOF
}

# Function to check endpoint health
health_check() {
    print_info "Checking endpoint health..."

    local response=$(curl -s ${BASE_URL}/health 2>&1)

    if echo "$response" | jq -e '.' > /dev/null 2>&1; then
        print_success "Health check passed"
        echo "$response" | jq '.'
        return 0
    else
        print_error "Health check failed"
        echo "$response"
        return 1
    fi
}

# Main benchmark suite
run_benchmarks() {
    print_info "Starting TRT-LLM Benchmark Suite"
    echo ""

    # Check health
    if ! health_check; then
        print_error "Endpoint not healthy. Exiting."
        exit 1
    fi
    echo ""

    # Initialize report
    init_report

    # Test 1: Short prompt, short completion
    echo ""
    print_info "Test 1: Short Prompt, Short Completion"
    test_completion "$SHORT_PROMPT" 50 "Test 1: Short Prompt (50 tokens)"
    sleep 2

    # Test 2: Short prompt, medium completion
    echo ""
    print_info "Test 2: Short Prompt, Medium Completion"
    test_completion "$SHORT_PROMPT" 150 "Test 2: Short Prompt (150 tokens)"
    sleep 2

    # Test 3: Medium prompt, medium completion
    echo ""
    print_info "Test 3: Medium Prompt, Medium Completion"
    test_completion "$MEDIUM_PROMPT" 100 "Test 3: Medium Prompt (100 tokens)"
    sleep 2

    # Test 4: Long prompt, short completion
    echo ""
    print_info "Test 4: Long Prompt, Short Completion"
    test_completion "$LONG_PROMPT" 50 "Test 4: Long Prompt (50 tokens)"
    sleep 2

    # Test 5: Latency test with short prompts
    echo ""
    print_info "Test 5: Latency Test (Short Prompts)"
    latency_test "$SHORT_PROMPT" 50 5 "Test 5: Latency Test (5 iterations)"

    # Add deployment info to report
    cat >> "$RESULTS_FILE" <<EOF

---

## Deployment Information

### Pod Details

\`\`\`
$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${DEPLOYMENT_NAME} -o wide)
\`\`\`

### Deployment Configuration

\`\`\`
$(kubectl get dynamographdeployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o yaml 2>/dev/null || echo "Not available")
\`\`\`

---

## Notes

- All tests use temperature=0.7
- Tests are run sequentially with 2-second delays
- Latency tests include 0.5-second delays between iterations
- Results may vary based on cluster load and resource availability

EOF

    print_success "Benchmark suite completed!"
    print_info "Results saved to: ${RESULTS_FILE}"
}

# Quick smoke test
smoke_test() {
    print_info "Running quick smoke test..."

    if health_check; then
        echo ""
        print_info "Testing single completion..."
        test_completion "Hello" 20 "Smoke Test"
        print_success "Smoke test passed!"
    else
        print_error "Smoke test failed - endpoint not healthy"
        exit 1
    fi
}

# Parse command line arguments
case "${1:-benchmark}" in
    benchmark)
        check_prereqs
        run_benchmarks
        ;;
    smoke)
        check_prereqs
        smoke_test
        ;;
    health)
        health_check
        ;;
    *)
        echo "Usage: $0 {benchmark|smoke|health}"
        echo ""
        echo "  benchmark  - Run full benchmark suite (default)"
        echo "  smoke      - Run quick smoke test"
        echo "  health     - Check endpoint health only"
        exit 1
        ;;
esac
