#!/bin/bash

# TRT-LLM Deployment Helper Functions
# Source this file to load all helper functions
# Usage: source trtllm-helpers.sh

# Environment Configuration
export NAMESPACE="dynamo-cloud"
export DEPLOYMENT_NAME="trtllm-disagg-qwen-full"
export MODEL_ID="Qwen/Qwen2.5-0.5B-Instruct"
export FRONTEND_SVC="${DEPLOYMENT_NAME}-frontend"
export LOCAL_PORT="8000"
export REMOTE_PORT="8000"

# Function to set pod names
refresh_pod_names() {
    export FRONTEND_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "^${DEPLOYMENT_NAME}-frontend-" | head -1 | awk '{print $1}')
    export PREFILL_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "^${DEPLOYMENT_NAME}-trtllmprefillworker-" | head -1 | awk '{print $1}')
    export DECODE_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "^${DEPLOYMENT_NAME}-trtllmdecodeworker-" | head -1 | awk '{print $1}')
}

# Function to deploy TRT-LLM
deploy_trtllm() {
    local YAML_FILE="${1:-trtllm-full-dynamograph-corrected.yaml}"

    kubectl apply -f "$YAML_FILE"
    echo "🚀 Deploying ${DEPLOYMENT_NAME}..."

    # Wait for pods to start
    echo "⏳ Waiting for pods to initialize..."
    sleep 15

    # Refresh pod names
    refresh_pod_names

    echo "🔍 Deployment Details:"
    echo "   Namespace: $NAMESPACE"
    echo "   Deployment: $DEPLOYMENT_NAME"
    echo "   Frontend Pod: $FRONTEND_POD"
    echo "   Prefill Pod: $PREFILL_POD"
    echo "   Decode Pod: $DECODE_POD"
    echo "   Frontend Service: $FRONTEND_SVC"
    echo "   Model: $MODEL_ID"
}

# Function to monitor pod status
monitor_pods() {
    echo "📊 Monitoring pod status..."
    kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${DEPLOYMENT_NAME} -w
}

# Function to check all pod status
check_status() {
    echo "📊 Current Pod Status:"
    refresh_pod_names
    kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${DEPLOYMENT_NAME} -o wide
    echo ""
    echo "🔍 Deployment Status:"
    kubectl get dynamographdeployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}
}

# Function to check frontend logs
check_f_logs() {
    refresh_pod_names
    if [ -z "$FRONTEND_POD" ]; then
        echo "❌ Frontend pod not found"
        return 1
    fi
    echo "📜 Checking frontend logs (${FRONTEND_POD})..."
    kubectl logs ${FRONTEND_POD} -n ${NAMESPACE} -f
}

# Function to check prefill worker logs
check_prefill_logs() {
    refresh_pod_names
    if [ -z "$PREFILL_POD" ]; then
        echo "❌ Prefill pod not found"
        return 1
    fi
    echo "📜 Checking prefill worker logs (${PREFILL_POD})..."
    kubectl logs ${PREFILL_POD} -n ${NAMESPACE} -f
}

# Function to check decode worker logs
check_decode_logs() {
    refresh_pod_names
    if [ -z "$DECODE_POD" ]; then
        echo "❌ Decode pod not found"
        return 1
    fi
    echo "📜 Checking decode worker logs (${DECODE_POD})..."
    kubectl logs ${DECODE_POD} -n ${NAMESPACE} -f
}

# Function to check all worker logs (last 50 lines each)
check_all_logs() {
    refresh_pod_names
    echo "📜 Frontend Logs (last 50 lines):"
    echo "=================================="
    kubectl logs ${FRONTEND_POD} -n ${NAMESPACE} --tail=50 2>/dev/null || echo "No logs available"

    echo -e "\n📜 Prefill Worker Logs (last 50 lines):"
    echo "========================================"
    kubectl logs ${PREFILL_POD} -n ${NAMESPACE} --tail=50 2>/dev/null || echo "No logs available"

    echo -e "\n📜 Decode Worker Logs (last 50 lines):"
    echo "========================================"
    kubectl logs ${DECODE_POD} -n ${NAMESPACE} --tail=50 2>/dev/null || echo "No logs available"
}

# Function to setup port-forward
setup_port_forward() {
    # Kill any existing port forwards
    pkill -f "port-forward svc/${FRONTEND_SVC}" 2>/dev/null || true

    # Start new port forward
    echo "🔌 Setting up port forward: localhost:${LOCAL_PORT} -> ${FRONTEND_SVC}:${REMOTE_PORT}"
    kubectl port-forward svc/${FRONTEND_SVC} ${LOCAL_PORT}:${REMOTE_PORT} -n ${NAMESPACE} &
    local PF_PID=$!

    echo "   Port forward PID: $PF_PID"
    echo "   Waiting for port forward to establish..."
    sleep 5

    # Check if port forward is running
    if ps -p $PF_PID > /dev/null 2>&1; then
        echo "✅ Port forward established successfully"
        return 0
    else
        echo "❌ Port forward failed to establish"
        return 1
    fi
}

# Function to test the API health
test_health() {
    echo "🧪 Testing health endpoint..."
    local response=$(curl -s http://localhost:${LOCAL_PORT}/health 2>/dev/null)

    if [ -n "$response" ]; then
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        return 0
    else
        echo "❌ No response from health endpoint"
        return 1
    fi
}

# Function to test the API with completion
test_completion() {
    local prompt="${1:-Write a short poem about artificial intelligence:}"
    local max_tokens="${2:-100}"

    echo -e "\n📝 Testing completion endpoint..."
    echo "   Prompt: $prompt"
    echo "   Max tokens: $max_tokens"
    echo ""

    curl -X POST http://localhost:${LOCAL_PORT}/v1/completions \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${MODEL_ID}\",
        \"prompt\": \"$prompt\",
        \"max_tokens\": $max_tokens,
        \"temperature\": 0.7
      }" | jq '.'
}

# Function to test chat completion
test_chat() {
    local message="${1:-Hello! Can you help me understand TensorRT-LLM?}"
    local max_tokens="${2:-150}"

    echo -e "\n💬 Testing chat completion endpoint..."
    echo "   Message: $message"
    echo "   Max tokens: $max_tokens"
    echo ""

    curl -X POST http://localhost:${LOCAL_PORT}/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${MODEL_ID}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"$message\"}],
        \"max_tokens\": $max_tokens,
        \"temperature\": 0.7
      }" | jq '.'
}

# Function to run quick smoke test
smoke_test() {
    echo "🧪 Running smoke test suite..."
    echo ""

    # Check pod status
    echo "1️⃣ Checking pod status..."
    check_status
    echo ""

    # Setup port forward if not already running
    if ! nc -z localhost ${LOCAL_PORT} 2>/dev/null; then
        echo "2️⃣ Setting up port forward..."
        setup_port_forward
    else
        echo "2️⃣ Port forward already running"
    fi
    echo ""

    # Test health
    echo "3️⃣ Testing health endpoint..."
    if test_health; then
        echo "✅ Health check passed"
    else
        echo "❌ Health check failed"
        return 1
    fi
    echo ""

    # Test completion
    echo "4️⃣ Testing completion endpoint..."
    if test_completion "Hello world" 20; then
        echo "✅ Completion test passed"
    else
        echo "❌ Completion test failed"
        return 1
    fi
    echo ""

    echo "✅ Smoke test complete!"
}

# Function to cleanup deployment
cleanup_deployment() {
    local YAML_FILE="${1:-trtllm-full-dynamograph-corrected.yaml}"

    echo "🧹 Cleaning up deployment..."
    kubectl delete -f "$YAML_FILE"
    pkill -f "port-forward svc/${FRONTEND_SVC}" 2>/dev/null || true
    echo "✅ Cleanup complete"
}

# Function to get metrics
get_metrics() {
    refresh_pod_names
    echo "📊 Getting metrics from pods..."

    echo -e "\nFrontend Pod Metrics:"
    kubectl exec ${FRONTEND_POD} -n ${NAMESPACE} -- curl -s http://localhost:9090/metrics 2>/dev/null | grep -E "^(dynamo_|http_)" | head -20 || echo "Metrics not available"

    echo -e "\nPrefill Worker Metrics:"
    kubectl exec ${PREFILL_POD} -n ${NAMESPACE} -- curl -s http://localhost:9090/metrics 2>/dev/null | grep -E "^(dynamo_|trtllm_)" | head -20 || echo "Metrics not available"
}

# Initialize on source
refresh_pod_names

# Print available functions
echo "✅ TRT-LLM Helper functions loaded. Available commands:"
echo ""
echo "   Deployment:"
echo "     deploy_trtllm [yaml_file]  - Deploy TRT-LLM service"
echo "     cleanup_deployment         - Remove deployment"
echo ""
echo "   Monitoring:"
echo "     check_status              - Check pod and deployment status"
echo "     monitor_pods              - Watch pod status (live)"
echo "     check_f_logs              - Check frontend logs (follow)"
echo "     check_prefill_logs        - Check prefill worker logs (follow)"
echo "     check_decode_logs         - Check decode worker logs (follow)"
echo "     check_all_logs            - Check all logs (last 50 lines)"
echo "     get_metrics               - Get metrics from pods"
echo ""
echo "   Testing:"
echo "     setup_port_forward        - Setup port forwarding"
echo "     test_health               - Test health endpoint"
echo "     test_completion [prompt] [max_tokens]  - Test completion API"
echo "     test_chat [message] [max_tokens]       - Test chat API"
echo "     smoke_test                - Run full smoke test suite"
echo ""
echo "   Environment:"
echo "     refresh_pod_names         - Refresh pod name variables"
echo ""
echo "🔍 Current Configuration:"
echo "   Namespace: $NAMESPACE"
echo "   Deployment: $DEPLOYMENT_NAME"
echo "   Model: $MODEL_ID"
echo "   Port: localhost:${LOCAL_PORT}"
