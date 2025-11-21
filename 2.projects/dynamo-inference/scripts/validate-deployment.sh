#!/bin/bash

# Deployment Validation Script for Dynamo Inference
# Validates all prerequisites and deployment health
# Usage: ./validate-deployment.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/environment.conf"
REPORT_FILE="/tmp/validation-report-$(date +%Y%m%d-%H%M%S).txt"
EXIT_ON_ERROR=${EXIT_ON_ERROR:-false}

# Load configuration if available
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Default values
NAMESPACE=${NAMESPACE:-dynamo-cloud}
REQUIRED_TOOLS=(kubectl jq curl)
OPTIONAL_TOOLS=(docker aws helm)

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       Dynamo Inference - Deployment Validation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Counters
ERRORS=0
WARNINGS=0
CHECKS=0

# Function to print messages
print_check() {
    ((CHECKS++))
    echo -e "${CYAN}[CHECK $CHECKS]${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    ((WARNINGS++))
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    ((ERRORS++))
    echo -e "  ${RED}✗${NC} $1"
    if [ "$EXIT_ON_ERROR" = "true" ]; then
        echo "Exiting due to error (EXIT_ON_ERROR=true)"
        exit 1
    fi
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

# Function to check command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to log to report file
log_report() {
    echo "$1" >> "$REPORT_FILE"
}

# Start report
{
    echo "Dynamo Inference Deployment Validation Report"
    echo "Generated: $(date)"
    echo "============================================="
    echo ""
} > "$REPORT_FILE"

# 1. Check Required Tools
check_required_tools() {
    print_check "Checking required system tools..."
    log_report "Required Tools Check:"

    local missing_tools=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command_exists "$tool"; then
            VERSION=$($tool version --short 2>/dev/null || $tool --version 2>/dev/null || echo "unknown")
            print_success "$tool is installed"
            log_report "  ✓ $tool: installed"
        else
            print_error "$tool is NOT installed (required)"
            log_report "  ✗ $tool: missing (required)"
            missing_tools+=("$tool")
        fi
    done

    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if command_exists "$tool"; then
            print_success "$tool is installed (optional)"
            log_report "  ✓ $tool: installed (optional)"
        else
            print_warning "$tool is not installed (optional)"
            log_report "  ⚠ $tool: missing (optional)"
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_info "Install missing tools with: sudo apt-get install -y ${missing_tools[*]}"
    fi
    echo ""
    log_report ""
}

# 2. Check Kubernetes Connectivity
check_kubernetes() {
    print_check "Checking Kubernetes cluster connectivity..."
    log_report "Kubernetes Connectivity:"

    if kubectl cluster-info >/dev/null 2>&1; then
        CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
        print_success "Connected to cluster: $CLUSTER_NAME"
        log_report "  ✓ Connected to: $CLUSTER_NAME"

        # Get cluster version
        K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || echo "unknown")
        print_info "Kubernetes version: $K8S_VERSION"
        log_report "  Version: $K8S_VERSION"

        # Check nodes
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        print_info "Cluster has $NODE_COUNT nodes"
        log_report "  Nodes: $NODE_COUNT"
    else
        print_error "Cannot connect to Kubernetes cluster"
        log_report "  ✗ Cannot connect to cluster"
        print_info "Check your kubeconfig or cluster status"
    fi
    echo ""
    log_report ""
}

# 3. Check Namespace
check_namespace() {
    print_check "Checking namespace: $NAMESPACE"
    log_report "Namespace Check ($NAMESPACE):"

    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_success "Namespace exists"
        log_report "  ✓ Namespace exists"

        # Check for resources in namespace
        POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        SVC_COUNT=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        print_info "Found $POD_COUNT pods, $SVC_COUNT services"
        log_report "  Resources: $POD_COUNT pods, $SVC_COUNT services"
    else
        print_warning "Namespace $NAMESPACE does not exist"
        log_report "  ⚠ Namespace does not exist"
        print_info "Run: kubectl create namespace $NAMESPACE"
    fi
    echo ""
    log_report ""
}

# 4. Check NVIDIA Dynamo Operator
check_dynamo_operator() {
    print_check "Checking NVIDIA Dynamo operator..."
    log_report "Dynamo Operator Check:"

    if kubectl get crd dynamographdeployments.dynamo.ai-dynamo.com >/dev/null 2>&1; then
        print_success "Dynamo CRD is installed"
        log_report "  ✓ CRD installed"

        # Check operator pods
        OPERATOR_POD=$(kubectl get pods --all-namespaces -l app=dynamo-operator --no-headers 2>/dev/null | head -1)
        if [ -n "$OPERATOR_POD" ]; then
            OPERATOR_NS=$(echo "$OPERATOR_POD" | awk '{print $1}')
            OPERATOR_NAME=$(echo "$OPERATOR_POD" | awk '{print $2}')
            OPERATOR_STATUS=$(echo "$OPERATOR_POD" | awk '{print $4}')
            print_success "Operator pod running: $OPERATOR_NAME (status: $OPERATOR_STATUS)"
            log_report "  ✓ Operator pod: $OPERATOR_NAME ($OPERATOR_STATUS)"
        else
            print_warning "Dynamo operator pod not found"
            log_report "  ⚠ Operator pod not found"
        fi
    else
        print_warning "Dynamo operator not installed"
        log_report "  ⚠ Dynamo operator not installed"
        print_info "Some deployment features will not work without the operator"
    fi
    echo ""
    log_report ""
}

# 5. Check GPU Resources
check_gpu_resources() {
    print_check "Checking GPU resources..."
    log_report "GPU Resources Check:"

    GPU_NODES=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | select(.status.capacity."nvidia.com/gpu" != null) | .metadata.name' || echo "")

    if [ -n "$GPU_NODES" ]; then
        GPU_COUNT=$(echo "$GPU_NODES" | wc -w)
        print_success "Found $GPU_COUNT GPU nodes"
        log_report "  ✓ GPU nodes: $GPU_COUNT"

        for node in $GPU_NODES; do
            GPU_PER_NODE=$(kubectl get node "$node" -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || echo "0")
            INSTANCE_TYPE=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}' 2>/dev/null || echo "unknown")
            print_info "  $node: $GPU_PER_NODE GPUs (type: $INSTANCE_TYPE)"
            log_report "    - $node: $GPU_PER_NODE GPUs ($INSTANCE_TYPE)"
        done

        # Check GPU driver
        DRIVER_POD=$(kubectl get pods --all-namespaces -l app=nvidia-device-plugin --no-headers 2>/dev/null | head -1)
        if [ -n "$DRIVER_POD" ]; then
            print_success "NVIDIA device plugin is running"
            log_report "  ✓ NVIDIA device plugin running"
        else
            print_warning "NVIDIA device plugin not found"
            log_report "  ⚠ NVIDIA device plugin not found"
        fi
    else
        print_error "No GPU nodes found in cluster"
        log_report "  ✗ No GPU nodes found"
        print_info "GPU nodes are required for model inference"
    fi
    echo ""
    log_report ""
}

# 6. Check ETCD Service
check_etcd() {
    print_check "Checking ETCD service..."
    log_report "ETCD Service Check:"

    # Try multiple namespaces
    ETCD_FOUND=false
    for ns in "$NAMESPACE" "default" "kube-system" "etcd"; do
        if kubectl get service -n "$ns" 2>/dev/null | grep -q etcd; then
            ETCD_SERVICE=$(kubectl get service -n "$ns" -o name 2>/dev/null | grep etcd | head -1 | cut -d/ -f2)
            if [ -n "$ETCD_SERVICE" ]; then
                ETCD_IP=$(kubectl get service "$ETCD_SERVICE" -n "$ns" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
                print_success "Found ETCD service: $ETCD_SERVICE in namespace $ns"
                print_info "ETCD endpoint: http://$ETCD_IP:2379"
                log_report "  ✓ ETCD service: $ETCD_SERVICE ($ns)"
                log_report "  Endpoint: http://$ETCD_IP:2379"
                ETCD_FOUND=true
                break
            fi
        fi
    done

    if [ "$ETCD_FOUND" = "false" ]; then
        print_warning "ETCD service not found"
        log_report "  ⚠ ETCD service not found"
        print_info "ETCD is required for NIXL benchmarks"
        print_info "Run: ./scripts/setup-all.sh to deploy ETCD"
    fi
    echo ""
    log_report ""
}

# 7. Check Secrets
check_secrets() {
    print_check "Checking required secrets..."
    log_report "Secrets Check:"

    # Check HuggingFace token
    if kubectl get secret hf-token-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        print_success "HuggingFace token secret exists"
        log_report "  ✓ HuggingFace token secret exists"
    else
        print_warning "HuggingFace token secret not found"
        log_report "  ⚠ HuggingFace token secret not found"
        print_info "Some models require HuggingFace authentication"
        print_info "Create with: HF_TOKEN=your_token ./scripts/setup-all.sh"
    fi

    # Check for image pull secrets
    PULL_SECRETS=$(kubectl get secrets -n "$NAMESPACE" --field-selector type=kubernetes.io/dockerconfigjson --no-headers 2>/dev/null | wc -l)
    if [ "$PULL_SECRETS" -gt 0 ]; then
        print_success "Found $PULL_SECRETS image pull secret(s)"
        log_report "  ✓ Image pull secrets: $PULL_SECRETS"
    else
        print_info "No image pull secrets configured"
        log_report "  ℹ No image pull secrets"
    fi
    echo ""
    log_report ""
}

# 8. Check Docker Images
check_docker_images() {
    print_check "Checking Docker images..."
    log_report "Docker Images Check:"

    if command_exists docker; then
        # Check for GenAI-Perf image
        if docker images | grep -q "tritonserver.*24.10-py3-sdk"; then
            print_success "GenAI-Perf SDK image is available"
            log_report "  ✓ GenAI-Perf SDK image available"
        else
            print_warning "GenAI-Perf SDK image not found locally"
            log_report "  ⚠ GenAI-Perf SDK image not found"
            print_info "Pull with: docker pull nvcr.io/nvidia/tritonserver:24.10-py3-sdk"
        fi

        # Check for dynamo images
        DYNAMO_IMAGES=$(docker images | grep -c "dynamo-" || echo "0")
        if [ "$DYNAMO_IMAGES" -gt 0 ]; then
            print_success "Found $DYNAMO_IMAGES Dynamo images"
            log_report "  ✓ Dynamo images: $DYNAMO_IMAGES"
        else
            print_info "No Dynamo images built locally"
            log_report "  ℹ No Dynamo images found"
        fi
    else
        print_warning "Docker not available, skipping image checks"
        log_report "  ⚠ Docker not available"
    fi
    echo ""
    log_report ""
}

# 9. Check Network Requirements
check_network() {
    print_check "Checking network requirements..."
    log_report "Network Check:"

    # Check for EFA support (AWS specific)
    EFA_NODES=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | select(.status.capacity."vpc.amazonaws.com/efa" != null) | .metadata.name' || echo "")

    if [ -n "$EFA_NODES" ]; then
        EFA_COUNT=$(echo "$EFA_NODES" | wc -w)
        print_success "Found $EFA_COUNT nodes with EFA support"
        log_report "  ✓ EFA nodes: $EFA_COUNT"
        for node in $EFA_NODES; do
            EFA_PER_NODE=$(kubectl get node "$node" -o jsonpath='{.status.capacity.vpc\.amazonaws\.com/efa}' 2>/dev/null || echo "0")
            print_info "  $node: $EFA_PER_NODE EFA devices"
            log_report "    - $node: $EFA_PER_NODE EFA devices"
        done
    else
        print_info "No EFA support detected (AWS specific feature)"
        log_report "  ℹ No EFA support detected"
    fi

    # Check for LoadBalancer support
    LB_SVC=$(kubectl get svc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name' | head -1)
    if [ -n "$LB_SVC" ]; then
        print_success "LoadBalancer service support available"
        log_report "  ✓ LoadBalancer support available"
    else
        print_info "No LoadBalancer services found"
        log_report "  ℹ No LoadBalancer services"
    fi
    echo ""
    log_report ""
}

# 10. Check Storage
check_storage() {
    print_check "Checking storage resources..."
    log_report "Storage Check:"

    # Check storage classes
    DEFAULT_SC=$(kubectl get storageclass -o json 2>/dev/null | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class"=="true") | .metadata.name' || echo "")

    if [ -n "$DEFAULT_SC" ]; then
        print_success "Default storage class: $DEFAULT_SC"
        log_report "  ✓ Default storage class: $DEFAULT_SC"
    else
        print_warning "No default storage class configured"
        log_report "  ⚠ No default storage class"
    fi

    # Check PVCs
    PVC_COUNT=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$PVC_COUNT" -gt 0 ]; then
        print_info "Found $PVC_COUNT persistent volume claims"
        log_report "  PVCs: $PVC_COUNT"
    fi
    echo ""
    log_report ""
}

# 11. Check Running Deployments
check_deployments() {
    print_check "Checking running deployments..."
    log_report "Running Deployments:"

    # Check for Dynamo deployments
    DYNAMO_DEPS=$(kubectl get dynamographdeployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$DYNAMO_DEPS" -gt 0 ]; then
        print_success "Found $DYNAMO_DEPS Dynamo deployments"
        log_report "  ✓ Dynamo deployments: $DYNAMO_DEPS"
        kubectl get dynamographdeployments -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r dep; do
            DEP_NAME=$(echo "$dep" | awk '{print $1}')
            print_info "  - $DEP_NAME"
            log_report "    - $DEP_NAME"
        done
    else
        print_info "No Dynamo deployments running"
        log_report "  ℹ No Dynamo deployments"
    fi

    # Check for standard deployments
    STD_DEPS=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$STD_DEPS" -gt 0 ]; then
        print_info "Found $STD_DEPS standard deployments"
        log_report "  Standard deployments: $STD_DEPS"
    fi
    echo ""
    log_report ""
}

# 12. Check Test Pods
check_test_pods() {
    print_check "Checking test pods..."
    log_report "Test Pods Check:"

    # Check for NIXL benchmark pods
    NIXL_PODS=$(kubectl get pods --all-namespaces 2>/dev/null | grep -c "nixl-bench" || echo "0")
    if [ "$NIXL_PODS" -gt 0 ]; then
        print_success "Found $NIXL_PODS NIXL benchmark pods"
        log_report "  ✓ NIXL pods: $NIXL_PODS"
    else
        print_info "No NIXL benchmark pods running"
        log_report "  ℹ No NIXL pods"
    fi

    # Check for UCX test pods
    UCX_PODS=$(kubectl get pods --all-namespaces 2>/dev/null | grep -c "ucx-test" || echo "0")
    if [ "$UCX_PODS" -gt 0 ]; then
        print_success "Found $UCX_PODS UCX test pods"
        log_report "  ✓ UCX pods: $UCX_PODS"
    else
        print_info "No UCX test pods running"
        log_report "  ℹ No UCX pods"
    fi
    echo ""
    log_report ""
}

# Generate Summary
generate_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    Validation Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    {
        echo ""
        echo "============================================="
        echo "SUMMARY"
        echo "============================================="
        echo "Total Checks: $CHECKS"
        echo "Errors: $ERRORS"
        echo "Warnings: $WARNINGS"
    } >> "$REPORT_FILE"

    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}✓ All critical checks passed!${NC}"
        echo "Status: PASSED" >> "$REPORT_FILE"

        if [ $WARNINGS -gt 0 ]; then
            echo -e "${YELLOW}⚠ $WARNINGS warning(s) found (non-critical)${NC}"
            echo "Warnings: $WARNINGS (non-critical)" >> "$REPORT_FILE"
        fi

        echo ""
        echo "Deployment is ready for:"
        echo "  ✓ Basic operations"

        if [ "$GPU_NODES" ]; then
            echo "  ✓ GPU workloads"
        fi

        if [ "$ETCD_FOUND" = "true" ]; then
            echo "  ✓ NIXL benchmarks"
        fi

        if kubectl get crd dynamographdeployments.dynamo.ai-dynamo.com >/dev/null 2>&1; then
            echo "  ✓ Dynamo deployments"
        fi

    else
        echo -e "${RED}✗ $ERRORS error(s) found!${NC}"
        echo "Status: FAILED" >> "$REPORT_FILE"
        echo ""
        echo "Please fix the errors above before proceeding."
        echo "Run './scripts/setup-all.sh' to fix most issues automatically."
    fi

    echo ""
    echo "Full report saved to: $REPORT_FILE"
    echo ""

    # Show next steps
    if [ $ERRORS -eq 0 ]; then
        echo "Next steps:"
        echo "1. Deploy a model: ./scripts/deploy-with-validation.sh"
        echo "2. Run benchmarks: ./benchmarks/vllm-genai-perf/master-benchmark.sh"
        echo "3. View report: cat $REPORT_FILE"
    else
        echo "To fix issues:"
        echo "1. Run setup: ./scripts/setup-all.sh"
        echo "2. Re-validate: ./scripts/validate-deployment.sh"
        echo "3. View report: cat $REPORT_FILE"
    fi

    echo ""

    # Return appropriate exit code
    if [ $ERRORS -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Main validation flow
main() {
    # Run all checks
    check_required_tools
    check_kubernetes
    check_namespace
    check_dynamo_operator
    check_gpu_resources
    check_etcd
    check_secrets
    check_docker_images
    check_network
    check_storage
    check_deployments
    check_test_pods

    # Generate summary
    generate_summary
}

# Run main function
main "$@"