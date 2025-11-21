#!/bin/bash

# Master Setup Script for Dynamo Inference
# Handles complete one-time setup for deployment and testing
# Usage:
#   HF_TOKEN=your_token ./setup-all.sh
#   or with all options:
#   HF_TOKEN=your_token NAMESPACE=my-namespace SKIP_ETCD=false ./setup-all.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration defaults (can be overridden via environment)
NAMESPACE=${NAMESPACE:-dynamo-cloud}
ETCD_NAMESPACE=${ETCD_NAMESPACE:-$NAMESPACE}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-public.ecr.aws}
AWS_REGION=${AWS_REGION:-us-east-2}
HF_TOKEN=${HF_TOKEN:-}  # HuggingFace token from environment
SKIP_OPERATOR_CHECK=${SKIP_OPERATOR_CHECK:-false}
SKIP_ETCD=${SKIP_ETCD:-false}
SKIP_DOCKER_PULL=${SKIP_DOCKER_PULL:-false}
NON_INTERACTIVE=${NON_INTERACTIVE:-true}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/environment.conf"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       Dynamo Inference - Complete Setup Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Function to print status messages
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Kubernetes connectivity
check_kubernetes() {
    print_status "Checking Kubernetes connectivity..."
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        print_error "Please ensure kubectl is configured and you have cluster access"
        exit 1
    fi
    print_success "Kubernetes cluster is accessible"
}

# Function to check for NVIDIA Dynamo operator
check_dynamo_operator() {
    print_status "Checking for NVIDIA Dynamo operator..."

    # Skip check if requested
    if [ "$SKIP_OPERATOR_CHECK" = "true" ]; then
        print_warning "Skipping Dynamo operator check (SKIP_OPERATOR_CHECK=true)"
        return 1
    fi

    # Check for Dynamo CRDs
    if kubectl get crd dynamographdeployments.dynamo.ai-dynamo.com >/dev/null 2>&1; then
        print_success "NVIDIA Dynamo operator is installed"
        return 0
    else
        print_warning "NVIDIA Dynamo operator not found"
        echo "To install the NVIDIA Dynamo operator:"
        echo "1. Contact NVIDIA for access to the Dynamo operator"
        echo "2. Follow the installation guide at: https://docs.nvidia.com/dynamo"
        echo ""
        echo "Continuing without Dynamo operator. Some features may not work."
        echo "Set SKIP_OPERATOR_CHECK=true to suppress this warning."
        return 1
    fi
}

# Function to create namespace
create_namespace() {
    print_status "Setting up namespace: $NAMESPACE"

    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_success "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace "$NAMESPACE"
        print_success "Created namespace $NAMESPACE"
    fi
}

# Function to create HuggingFace token secret
create_hf_secret() {
    print_status "Setting up HuggingFace token secret..."

    # Check if secret already exists
    if kubectl get secret hf-token-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        if [ -n "$HF_TOKEN" ]; then
            print_status "Updating existing HuggingFace token secret"
            kubectl delete secret hf-token-secret -n "$NAMESPACE" >/dev/null 2>&1
        else
            print_success "HuggingFace token secret already exists"
            return 0
        fi
    fi

    # Create secret if token provided
    if [ -z "$HF_TOKEN" ]; then
        print_warning "No HuggingFace token provided (set HF_TOKEN environment variable)"
        print_warning "Some models may not be accessible without this token"
        print_warning "To set: export HF_TOKEN=your_token_here"
    else
        kubectl create secret generic hf-token-secret \
            --from-literal=HF_TOKEN="$HF_TOKEN" \
            -n "$NAMESPACE" >/dev/null 2>&1
        print_success "Created HuggingFace token secret"
    fi
}

# Function to deploy ETCD service
deploy_etcd() {
    if [ "$SKIP_ETCD" = "true" ]; then
        print_warning "Skipping ETCD deployment (SKIP_ETCD=true)"
        return 0
    fi

    print_status "Checking ETCD service..."

    if kubectl get service etcd-service -n "$ETCD_NAMESPACE" >/dev/null 2>&1; then
        print_success "ETCD service already exists"
        return 0
    fi

    print_status "Deploying ETCD service..."

    # Create ETCD deployment YAML
    cat > /tmp/etcd-deployment.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: etcd-service
  namespace: $ETCD_NAMESPACE
spec:
  ports:
  - port: 2379
    name: client
  - port: 2380
    name: peer
  selector:
    app: etcd
  type: ClusterIP
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: etcd
  namespace: $ETCD_NAMESPACE
spec:
  serviceName: etcd
  replicas: 1
  selector:
    matchLabels:
      app: etcd
  template:
    metadata:
      labels:
        app: etcd
    spec:
      containers:
      - name: etcd
        image: quay.io/coreos/etcd:v3.5.9
        env:
        - name: ETCD_NAME
          value: "etcd0"
        - name: ETCD_DATA_DIR
          value: "/var/etcd/data"
        - name: ETCD_LISTEN_CLIENT_URLS
          value: "http://0.0.0.0:2379"
        - name: ETCD_ADVERTISE_CLIENT_URLS
          value: "http://etcd-service:2379"
        - name: ETCD_LISTEN_PEER_URLS
          value: "http://0.0.0.0:2380"
        - name: ETCD_INITIAL_ADVERTISE_PEER_URLS
          value: "http://etcd-0.etcd:2380"
        - name: ETCD_INITIAL_CLUSTER
          value: "etcd0=http://etcd-0.etcd:2380"
        - name: ETCD_INITIAL_CLUSTER_STATE
          value: "new"
        - name: ETCD_INITIAL_CLUSTER_TOKEN
          value: "etcd-cluster-1"
        ports:
        - containerPort: 2379
          name: client
        - containerPort: 2380
          name: peer
        volumeMounts:
        - name: etcd-storage
          mountPath: /var/etcd
  volumeClaimTemplates:
  - metadata:
      name: etcd-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
EOF

    kubectl apply -f /tmp/etcd-deployment.yaml

    # Wait for ETCD to be ready
    print_status "Waiting for ETCD to be ready..."
    kubectl wait --for=condition=ready pod -l app=etcd -n "$ETCD_NAMESPACE" --timeout=60s

    print_success "ETCD service deployed successfully"
}

# Function to install Python dependencies
install_python_deps() {
    print_status "Installing Python dependencies..."

    # Check if pip is available
    if ! command_exists pip3; then
        print_warning "pip3 not found, skipping Python dependencies"
        return 1
    fi

    # Core dependencies
    pip3 install --user pyyaml requests tabulate jinja2 >/dev/null 2>&1

    # Optional dependencies for visualization
    pip3 install --user pandas matplotlib seaborn >/dev/null 2>&1 || true

    print_success "Python dependencies installed"
}

# Function to pull required Docker images
pull_docker_images() {
    if [ "$SKIP_DOCKER_PULL" = "true" ]; then
        print_warning "Skipping Docker image pulls (SKIP_DOCKER_PULL=true)"
        return 0
    fi

    print_status "Checking required Docker images..."

    # Check if Docker is available
    if ! command_exists docker; then
        print_warning "Docker not found, skipping image pulls"
        return 1
    fi

    # GenAI-Perf SDK image
    print_status "Pulling GenAI-Perf SDK image..."
    if docker pull nvcr.io/nvidia/tritonserver:24.10-py3-sdk >/dev/null 2>&1; then
        print_success "GenAI-Perf SDK image pulled"
    else
        print_warning "Failed to pull GenAI-Perf SDK image (may require NVIDIA NGC access)"
    fi
}

# Function to check system tools
check_system_tools() {
    print_status "Checking required system tools..."

    local missing_tools=()

    for tool in kubectl jq curl; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        else
            print_success "$tool is installed"
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_warning "Missing tools: ${missing_tools[*]}"
        echo "Please install missing tools:"
        echo "  sudo apt-get update && sudo apt-get install -y ${missing_tools[*]}"
    fi
}

# Function to create environment configuration
create_environment_config() {
    print_status "Creating environment configuration..."

    # Create config directory
    mkdir -p "${PROJECT_ROOT}/config"

    # Detect cluster information
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

    # Try to detect ETCD endpoint
    ETCD_IP=""
    if kubectl get service etcd-service -n "$ETCD_NAMESPACE" >/dev/null 2>&1; then
        ETCD_IP=$(kubectl get service etcd-service -n "$ETCD_NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    fi

    # Create configuration file
    cat > "$CONFIG_FILE" <<EOF
# Dynamo Inference Environment Configuration
# Generated on $(date)

# Kubernetes Configuration
export NAMESPACE="${NAMESPACE}"
export ETCD_NAMESPACE="${ETCD_NAMESPACE}"
export CLUSTER_NAME="${CLUSTER_NAME}"
export NODE_COUNT="${NODE_COUNT}"

# Container Registry Configuration
export CONTAINER_REGISTRY="${CONTAINER_REGISTRY}"
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="\${AWS_ACCOUNT_ID:-YOUR_ACCOUNT_ID}"

# ETCD Configuration
export ETCD_SERVICE="etcd-service"
export ETCD_IP="${ETCD_IP}"
export ETCD_ENDPOINT="http://\${ETCD_IP:-etcd-service}:2379"

# Image Tags
export DYNAMO_BASE_TAG="v0.6.1.dev.b573bc198"
export TRTLLM_TAG="dynamo-trtllm:latest"
export VLLM_TAG="dynamo-vllm:latest"

# Model Configuration
export DEFAULT_MODEL="meta-llama/Llama-2-7b-chat-hf"
export TENSOR_PARALLEL_SIZE="1"

# Benchmark Configuration
export BENCHMARK_ITERATIONS="100"
export BENCHMARK_WARMUP="10"

# Feature Flags
export ENABLE_NIXLBENCH_FIX="1"
export ETCD_CPP_API_DISABLE_URI_VALIDATION="1"
EOF

    print_success "Environment configuration created at $CONFIG_FILE"
}

# Function to validate GPU availability
check_gpu_resources() {
    print_status "Checking GPU resources in cluster..."

    GPU_NODES=$(kubectl get nodes -o json | jq '[.items[] | select(.status.capacity."nvidia.com/gpu" != null)] | length')

    if [ "$GPU_NODES" -eq 0 ]; then
        print_warning "No GPU nodes found in cluster"
        echo "GPU nodes are required for model inference"
    else
        TOTAL_GPUS=$(kubectl get nodes -o json | jq '[.items[].status.capacity."nvidia.com/gpu" // "0" | tonumber] | add')
        print_success "Found $GPU_NODES GPU nodes with $TOTAL_GPUS total GPUs"
    fi
}

# Function to create setup summary
create_setup_summary() {
    local SUMMARY_FILE="${PROJECT_ROOT}/setup-summary.txt"

    cat > "$SUMMARY_FILE" <<EOF
Dynamo Inference Setup Summary
Generated: $(date)

Cluster Information:
- Context: $CLUSTER_NAME
- Namespace: $NAMESPACE
- Node Count: $NODE_COUNT
- GPU Nodes: ${GPU_NODES:-0}
- Total GPUs: ${TOTAL_GPUS:-0}

Services:
- ETCD: ${ETCD_IP:-Not configured}
- Dynamo Operator: $(kubectl get crd dynamographdeployments.dynamo.ai-dynamo.com >/dev/null 2>&1 && echo "Installed" || echo "Not installed")

Configuration:
- Config File: $CONFIG_FILE
- Container Registry: $CONTAINER_REGISTRY
- AWS Region: $AWS_REGION

Next Steps:
1. Source the environment configuration:
   source $CONFIG_FILE

2. Deploy a model:
   ./scripts/deploy-with-validation.sh

3. Run benchmarks:
   ./benchmarks/vllm-genai-perf/master-benchmark.sh

For more information, see QUICKSTART.md
EOF

    print_success "Setup summary created at $SUMMARY_FILE"
}

# Main setup flow
main() {
    echo "Starting complete setup process..."
    echo ""

    # Step 1: Check prerequisites
    check_kubernetes
    check_system_tools

    # Step 2: Setup Kubernetes resources
    create_namespace
    check_dynamo_operator

    # Step 3: Create secrets
    create_hf_secret

    # Step 4: Deploy services
    deploy_etcd

    # Step 5: Install dependencies
    install_python_deps
    pull_docker_images

    # Step 6: Check resources
    check_gpu_resources

    # Step 7: Create configuration
    create_environment_config

    # Step 8: Create summary
    create_setup_summary

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           Setup completed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Configuration saved to: $CONFIG_FILE"
    echo "Setup summary saved to: ${PROJECT_ROOT}/setup-summary.txt"
    echo ""
    echo "To use this configuration in your session:"
    echo "  source $CONFIG_FILE"
    echo ""
    echo "To deploy a model:"
    echo "  ./scripts/deploy-with-validation.sh"
    echo ""
}

# Run main function
main "$@"