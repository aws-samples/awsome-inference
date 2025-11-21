#!/bin/bash

# Environment Configuration Script for Dynamo Inference
# Auto-detects cluster configuration and replaces hardcoded values
# Usage: ./configure-environment.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/environment.conf"
BACKUP_DIR="${PROJECT_ROOT}/config/backups"

# Default configuration
NAMESPACE=${NAMESPACE:-dynamo-cloud}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-public.ecr.aws}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-YOUR_ACCOUNT_ID}
AWS_REGION=${AWS_REGION:-us-east-2}

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       Dynamo Inference - Environment Configuration${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Function to print messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect ETCD endpoint
detect_etcd_endpoint() {
    print_status "Detecting ETCD endpoint..."

    # Try to find ETCD service in various namespaces
    for ns in "$NAMESPACE" "default" "kube-system" "etcd"; do
        if kubectl get service -n "$ns" 2>/dev/null | grep -q etcd; then
            ETCD_SERVICE=$(kubectl get service -n "$ns" -o name 2>/dev/null | grep etcd | head -1 | cut -d/ -f2)
            if [ -n "$ETCD_SERVICE" ]; then
                ETCD_IP=$(kubectl get service "$ETCD_SERVICE" -n "$ns" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
                if [ -n "$ETCD_IP" ]; then
                    print_success "Found ETCD service: $ETCD_SERVICE in namespace $ns"
                    print_success "ETCD IP: $ETCD_IP"
                    ETCD_NAMESPACE="$ns"
                    return 0
                fi
            fi
        fi
    done

    # Check for ETCD pods
    ETCD_POD=$(kubectl get pods --all-namespaces -o wide 2>/dev/null | grep etcd | head -1)
    if [ -n "$ETCD_POD" ]; then
        ETCD_POD_NAME=$(echo "$ETCD_POD" | awk '{print $2}')
        ETCD_POD_NS=$(echo "$ETCD_POD" | awk '{print $1}')
        ETCD_POD_IP=$(echo "$ETCD_POD" | awk '{print $7}')
        print_warning "Found ETCD pod but no service: $ETCD_POD_NAME"
        print_warning "Consider creating a service for stable endpoint"
        ETCD_IP="$ETCD_POD_IP"
        ETCD_NAMESPACE="$ETCD_POD_NS"
        return 1
    fi

    print_warning "No ETCD service or pods found"
    ETCD_IP=""
    return 1
}

# Function to detect container registry
detect_container_registry() {
    print_status "Detecting container registry..."

    # Check if AWS CLI is available and configured
    if command -v aws >/dev/null 2>&1; then
        # Try to get AWS account ID
        DETECTED_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        if [ -n "$DETECTED_ACCOUNT_ID" ]; then
            AWS_ACCOUNT_ID="$DETECTED_ACCOUNT_ID"
            print_success "Detected AWS Account ID: $AWS_ACCOUNT_ID"
        fi

        # Try to get AWS region
        DETECTED_REGION=$(aws configure get region 2>/dev/null || echo "")
        if [ -n "$DETECTED_REGION" ]; then
            AWS_REGION="$DETECTED_REGION"
            print_success "Detected AWS Region: $AWS_REGION"
        fi

        # Check for ECR repositories
        if aws ecr describe-repositories --region "$AWS_REGION" >/dev/null 2>&1; then
            CONTAINER_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            print_success "Using ECR registry: $CONTAINER_REGISTRY"
        fi
    else
        print_warning "AWS CLI not available, using default registry settings"
    fi
}

# Function to detect GPU nodes
detect_gpu_nodes() {
    print_status "Detecting GPU nodes..."

    GPU_NODES=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | select(.status.capacity."nvidia.com/gpu" != null) | .metadata.name' | tr '\n' ' ')

    if [ -n "$GPU_NODES" ]; then
        GPU_COUNT=$(echo "$GPU_NODES" | wc -w)
        print_success "Found $GPU_COUNT GPU nodes: $GPU_NODES"

        # Get instance type of first GPU node
        FIRST_GPU_NODE=$(echo "$GPU_NODES" | awk '{print $1}')
        INSTANCE_TYPE=$(kubectl get node "$FIRST_GPU_NODE" -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}' 2>/dev/null || echo "unknown")
        print_success "GPU instance type: $INSTANCE_TYPE"
    else
        print_warning "No GPU nodes detected"
        GPU_COUNT=0
        INSTANCE_TYPE="none"
    fi
}

# Function to detect test pods
detect_test_pods() {
    print_status "Detecting test pods..."

    # Find nixl-bench pods
    NIXL_PODS=$(kubectl get pods --all-namespaces -o wide 2>/dev/null | grep -E "nixl-bench|ucx-test" | awk '{print $2"@"$1"@"$7}')

    if [ -n "$NIXL_PODS" ]; then
        print_success "Found test pods:"
        echo "$NIXL_PODS" | while IFS='@' read -r pod ns ip; do
            echo "  - $pod in namespace $ns (IP: $ip)"
        done
    else
        print_warning "No test pods found"
    fi
}

# Function to backup existing scripts
backup_scripts() {
    print_status "Creating backup of existing scripts..."

    mkdir -p "$BACKUP_DIR"
    BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_PATH="${BACKUP_DIR}/backup-${BACKUP_TIMESTAMP}"

    # Create backup
    if [ -d "${SCRIPT_DIR}" ]; then
        cp -r "${SCRIPT_DIR}" "${BACKUP_PATH}" 2>/dev/null || true
        print_success "Backup created at: ${BACKUP_PATH}"
    fi
}

# Function to update script files with placeholders
update_script_files() {
    print_status "Updating script files with detected values..."

    # List of files to update
    SCRIPTS_TO_UPDATE=(
        "${SCRIPT_DIR}/ucx-all-nics.sh"
        "${SCRIPT_DIR}/ucx-srd-multi-nic.sh"
        "${SCRIPT_DIR}/nixl-benchmark-test.sh"
        "${SCRIPT_DIR}/quick-deploy.sh"
        "${SCRIPT_DIR}/apply-nixlbench-patch.sh"
        "${SCRIPT_DIR}/build-trtllm-fixed.sh"
        "${PROJECT_ROOT}/benchmarks/nixlbench-libfabric/run-libfabric-test.sh"
        "${PROJECT_ROOT}/benchmarks/nixlbench-ucx/run-ucx-test.sh"
    )

    for script in "${SCRIPTS_TO_UPDATE[@]}"; do
        if [ -f "$script" ]; then
            print_status "Updating $(basename "$script")..."

            # Create temp file
            TEMP_FILE=$(mktemp)

            # Replace hardcoded values
            sed \
                -e "s/058264135704\.dkr\.ecr\.us-east-2\.amazonaws\.com/\${CONTAINER_REGISTRY}/g" \
                -e "s/058264135704/\${AWS_ACCOUNT_ID}/g" \
                -e "s/10\.1\.238\.41/\${TEST_NODE_IP}/g" \
                -e "s/10\.1\.25\.101/\${ETCD_IP}/g" \
                -e "s/172\.20\.91\.68/\${ETCD_IP}/g" \
                -e "s/etcd-service:2379/\${ETCD_ENDPOINT}/g" \
                -e "s/namespace: dynamo-cloud/namespace: \${NAMESPACE}/g" \
                -e "s/-n dynamo-cloud/-n \${NAMESPACE}/g" \
                "$script" > "$TEMP_FILE"

            # Add sourcing of config at the beginning if not present
            if ! grep -q "environment.conf" "$TEMP_FILE"; then
                {
                    head -1 "$TEMP_FILE"
                    echo ""
                    echo "# Source environment configuration"
                    echo "CONFIG_FILE=\"\$(dirname \"\$(dirname \"\${BASH_SOURCE[0]}\")\")}/config/environment.conf\""
                    echo "[ -f \"\$CONFIG_FILE\" ] && source \"\$CONFIG_FILE\""
                    echo ""
                    tail -n +2 "$TEMP_FILE"
                } > "${TEMP_FILE}.new"
                mv "${TEMP_FILE}.new" "$TEMP_FILE"
            fi

            # Replace original file
            mv "$TEMP_FILE" "$script"
            chmod +x "$script"
            print_success "Updated $(basename "$script")"
        fi
    done
}

# Function to create environment configuration
create_config_file() {
    print_status "Creating environment configuration file..."

    mkdir -p "$(dirname "$CONFIG_FILE")"

    cat > "$CONFIG_FILE" <<EOF
# Dynamo Inference Environment Configuration
# Auto-generated on $(date)
# This file is sourced by all scripts for consistent configuration

# Cluster Configuration
export NAMESPACE="${NAMESPACE}"
export CLUSTER_NAME="$(kubectl config current-context 2>/dev/null || echo 'unknown')"

# Container Registry
export CONTAINER_REGISTRY="${CONTAINER_REGISTRY}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export AWS_REGION="${AWS_REGION}"

# ETCD Configuration
export ETCD_NAMESPACE="${ETCD_NAMESPACE:-$NAMESPACE}"
export ETCD_IP="${ETCD_IP}"
export ETCD_SERVICE="${ETCD_SERVICE:-etcd-service}"
export ETCD_ENDPOINT="http://\${ETCD_IP:-\${ETCD_SERVICE}}:2379"
export ETCD_CPP_API_DISABLE_URI_VALIDATION="1"

# GPU Configuration
export GPU_NODES="${GPU_NODES}"
export GPU_COUNT="${GPU_COUNT:-0}"
export INSTANCE_TYPE="${INSTANCE_TYPE:-unknown}"

# Image Configuration
export DYNAMO_BASE_TAG="v0.6.1.dev.b573bc198"
export TRTLLM_TAG="dynamo-trtllm:latest"
export VLLM_TAG="dynamo-vllm:latest"
export GENAI_PERF_IMAGE="nvcr.io/nvidia/tritonserver:24.10-py3-sdk"

# Model Configuration
export DEFAULT_MODEL="${DEFAULT_MODEL:-meta-llama/Llama-2-7b-chat-hf}"
export TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"

# Benchmark Configuration
export BENCHMARK_ITERATIONS="${BENCHMARK_ITERATIONS:-100}"
export BENCHMARK_WARMUP="${BENCHMARK_WARMUP:-10}"

# NIXL Configuration
export FI_PROVIDER="${FI_PROVIDER:-efa}"
export FI_HMEM_DISABLE_P2P="${FI_HMEM_DISABLE_P2P:-0}"
export UCX_NET_DEVICES="${UCX_NET_DEVICES:-all}"

# Test Pod IPs (will be auto-detected at runtime)
export TEST_NODE_IP=""
export TEST_NODE2_IP=""

# Feature Flags
export ENABLE_NIXLBENCH_FIX="1"
export NON_INTERACTIVE="true"

# Helper function to get pod IPs dynamically
get_test_pod_ips() {
    local pod1=\$(kubectl get pod nixl-bench-node1 -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    local pod2=\$(kubectl get pod nixl-bench-node2 -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    export TEST_NODE_IP="\${pod1}"
    export TEST_NODE2_IP="\${pod2}"
}

# Helper function to get ETCD endpoint dynamically
get_etcd_endpoint() {
    if [ -z "\$ETCD_IP" ]; then
        local etcd_ip=\$(kubectl get service \${ETCD_SERVICE} -n \${ETCD_NAMESPACE} -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
        export ETCD_IP="\${etcd_ip}"
        export ETCD_ENDPOINT="http://\${ETCD_IP:-\${ETCD_SERVICE}}:2379"
    fi
}
EOF

    print_success "Configuration file created at: $CONFIG_FILE"
}

# Function to validate configuration
validate_configuration() {
    print_status "Validating configuration..."

    local issues=0

    # Check kubectl connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        ((issues++))
    else
        print_success "Kubernetes cluster is accessible"
    fi

    # Check namespace exists
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_success "Namespace $NAMESPACE exists"
    else
        print_warning "Namespace $NAMESPACE does not exist (will be created during setup)"
    fi

    # Check for GPU resources
    if [ "$GPU_COUNT" -eq 0 ]; then
        print_warning "No GPU nodes found - GPU workloads will not run"
    fi

    # Check for ETCD
    if [ -z "$ETCD_IP" ]; then
        print_warning "ETCD not detected - NIXL benchmarks will require ETCD setup"
    fi

    if [ $issues -gt 0 ]; then
        print_error "Found $issues configuration issues"
        return 1
    else
        print_success "Configuration validation passed"
        return 0
    fi
}

# Main configuration flow
main() {
    print_status "Starting environment configuration..."
    echo ""

    # Step 1: Create backups
    backup_scripts

    # Step 2: Detect environment
    detect_etcd_endpoint
    detect_container_registry
    detect_gpu_nodes
    detect_test_pods

    # Step 3: Update script files
    update_script_files

    # Step 4: Create configuration file
    create_config_file

    # Step 5: Validate configuration
    validate_configuration

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}       Environment configuration completed!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Configuration saved to: $CONFIG_FILE"
    echo ""
    echo "To use this configuration:"
    echo "  source $CONFIG_FILE"
    echo ""
    echo "Next steps:"
    echo "1. Run setup if not done: ./scripts/setup-all.sh"
    echo "2. Deploy services: ./scripts/deploy-with-validation.sh"
    echo "3. Run benchmarks: ./benchmarks/vllm-genai-perf/master-benchmark.sh"
    echo ""

    # Show detected configuration summary
    echo "Detected Configuration:"
    echo "  Namespace: $NAMESPACE"
    echo "  Container Registry: $CONTAINER_REGISTRY"
    echo "  AWS Account: $AWS_ACCOUNT_ID"
    echo "  AWS Region: $AWS_REGION"
    echo "  ETCD IP: ${ETCD_IP:-Not detected}"
    echo "  GPU Nodes: $GPU_COUNT"
    echo "  Instance Type: $INSTANCE_TYPE"
}

# Run main function
main "$@"