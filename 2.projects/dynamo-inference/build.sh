#!/bin/bash
#
# Dynamo Inference on AWS - Build Script
# Build EFA-enabled Docker images for NVIDIA Dynamo inference on AWS
#

set -e

# Default values
REGISTRY=""
TAG="latest"
BUILD_TARGET="all"
PUSH=false
NO_CACHE=false
CUDA_ARCH=""  # Will use default from Dockerfile if not specified

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build EFA-enabled Docker images for Dynamo inference on AWS"
    echo ""
    echo "Options:"
    echo "  -r, --registry REGISTRY   Container registry (e.g., public.ecr.aws/xxxxx)"
    echo "  -t, --tag TAG             Image tag (default: latest)"
    echo "  -b, --build TARGET        Build target: efa, trtllm, vllm, all (default: all)"
    echo "  -a, --arch ARCH           CUDA architecture: 80 (A100), 86 (A10), 90 (H100) (optional)"
    echo "  -p, --push                Push images to registry after build"
    echo "  -n, --no-cache            Build without Docker cache"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build all images locally"
    echo "  $0 -b efa                             # Build only base EFA image"
    echo "  $0 -b efa -a 90                       # Build base EFA image for H100 GPUs"
    echo "  $0 -b trtllm -a 80                    # Build TensorRT-LLM for A100 GPUs"
    echo "  $0 -r public.ecr.aws/v9l4g5s4 -p     # Build and push to ECR"
    echo "  $0 -t v1.0.0 -p -a 86                 # Build for A10 GPUs with specific tag and push"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_TARGET="$2"
            shift 2
            ;;
        -a|--arch)
            CUDA_ARCH="$2"
            shift 2
            ;;
        -p|--push)
            PUSH=true
            shift
            ;;
        -n|--no-cache)
            NO_CACHE=true
            shift
            ;;
        -h|--help)
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

# Set cache option
CACHE_OPT=""
if [ "$NO_CACHE" = true ]; then
    CACHE_OPT="--no-cache"
fi

# Image names
EFA_IMAGE="aws-efa-dynamo"
TRTLLM_IMAGE="dynamo-trtllm-efa"
VLLM_IMAGE="dynamo-vllm-efa"

# Set GPU suffix based on architecture
GPU_SUFFIX=""
if [ -n "$CUDA_ARCH" ]; then
    case $CUDA_ARCH in
        80)
            GPU_SUFFIX="-a100"  # SM80 - A100 GPUs (Compute Capability 8.0)
            ;;
        86)
            GPU_SUFFIX="-a10"   # SM86 - A10 GPUs (Compute Capability 8.6)
            ;;
        90)
            GPU_SUFFIX="-h100"  # SM90 - H100 GPUs (Compute Capability 9.0)
            ;;
        *)
            GPU_SUFFIX="-sm${CUDA_ARCH}"
            ;;
    esac
fi

build_efa() {
    local IMAGE_NAME="${EFA_IMAGE}${GPU_SUFFIX}"
    log_info "Building base EFA image: ${IMAGE_NAME}:${TAG}"

    # Add CUDA architecture build arg if specified
    ARCH_ARG=""
    if [ -n "$CUDA_ARCH" ]; then
        ARCH_ARG="--build-arg CUDA_ARCH=${CUDA_ARCH}"
        log_info "Using CUDA architecture: ${CUDA_ARCH}"
    fi

    docker build ${CACHE_OPT} ${ARCH_ARG} \
        -f Dockerfile.efa \
        -t ${IMAGE_NAME}:${TAG} \
        .

    if [ -n "$REGISTRY" ]; then
        docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}
        log_info "Tagged: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    fi
}

build_trtllm() {
    local IMAGE_NAME="${TRTLLM_IMAGE}${GPU_SUFFIX}"
    local BASE_IMAGE="${EFA_IMAGE}${GPU_SUFFIX}"
    log_info "Building TensorRT-LLM image: ${IMAGE_NAME}:${TAG}"

    # Check if base image exists
    if ! docker image inspect ${BASE_IMAGE}:${TAG} > /dev/null 2>&1; then
        log_warn "Base EFA image not found, building it first..."
        build_efa
    fi

    # Add CUDA architecture build arg if specified
    ARCH_ARG=""
    if [ -n "$CUDA_ARCH" ]; then
        ARCH_ARG="--build-arg CUDA_ARCH=${CUDA_ARCH}"
        log_info "Using CUDA architecture: ${CUDA_ARCH}"
    fi

    docker build ${CACHE_OPT} ${ARCH_ARG} \
        -f Dockerfile.dynamo-trtllm-efa \
        --build-arg BASE_IMAGE=${BASE_IMAGE}:${TAG} \
        -t ${IMAGE_NAME}:${TAG} \
        .

    if [ -n "$REGISTRY" ]; then
        docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}
        log_info "Tagged: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    fi
}

build_vllm() {
    local IMAGE_NAME="${VLLM_IMAGE}${GPU_SUFFIX}"
    local BASE_IMAGE="${EFA_IMAGE}${GPU_SUFFIX}"
    log_info "Building vLLM image: ${IMAGE_NAME}:${TAG}"

    # Check if base image exists
    if ! docker image inspect ${BASE_IMAGE}:${TAG} > /dev/null 2>&1; then
        log_warn "Base EFA image not found, building it first..."
        build_efa
    fi

    # Add CUDA architecture build arg if specified
    ARCH_ARG=""
    if [ -n "$CUDA_ARCH" ]; then
        ARCH_ARG="--build-arg CUDA_ARCH=${CUDA_ARCH}"
        log_info "Using CUDA architecture: ${CUDA_ARCH}"
    fi

    docker build ${CACHE_OPT} ${ARCH_ARG} \
        -f Dockerfile.dynamo-vllm-efa \
        --build-arg BASE_IMAGE=${BASE_IMAGE}:${TAG} \
        -t ${IMAGE_NAME}:${TAG} \
        .

    if [ -n "$REGISTRY" ]; then
        docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}
        log_info "Tagged: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    fi
}

# Function to check if ECR repository exists and create if needed
create_ecr_repo() {
    local repo_name=$1
    local registry_alias=""

    # Determine if it's public or private ECR
    if [[ "$REGISTRY" == *"public.ecr.aws"* ]]; then
        # Public ECR
        registry_alias=$(echo $REGISTRY | cut -d'/' -f2)

        # Check if repository exists
        if ! aws ecr-public describe-repositories --registry-id $registry_alias --repository-names $repo_name --region us-east-1 >/dev/null 2>&1; then
            log_info "Creating public ECR repository: $repo_name"
            aws ecr-public create-repository \
                --repository-name $repo_name \
                --registry-id $registry_alias \
                --region us-east-1 \
                --no-cli-pager 2>/dev/null || true
        else
            log_info "Repository $repo_name already exists"
        fi
    elif [[ "$REGISTRY" == *"dkr.ecr"* ]]; then
        # Private ECR
        local region=$(echo $REGISTRY | cut -d'.' -f4)

        # Check if repository exists
        if ! aws ecr describe-repositories --repository-names $repo_name --region $region >/dev/null 2>&1; then
            log_info "Creating private ECR repository: $repo_name"
            aws ecr create-repository \
                --repository-name $repo_name \
                --region $region \
                --image-scanning-configuration scanOnPush=true \
                --no-cli-pager 2>/dev/null || true
        else
            log_info "Repository $repo_name already exists"
        fi
    fi
}

# Function to authenticate with ECR
ecr_login() {
    if [[ "$REGISTRY" == *"public.ecr.aws"* ]]; then
        # Public ECR login
        log_info "Authenticating with public ECR..."
        aws ecr-public get-login-password --region us-east-1 | \
            docker login --username AWS --password-stdin $REGISTRY 2>/dev/null
    elif [[ "$REGISTRY" == *"dkr.ecr"* ]]; then
        # Private ECR login
        local region=$(echo $REGISTRY | cut -d'.' -f4)
        local account=$(echo $REGISTRY | cut -d'.' -f1)
        log_info "Authenticating with private ECR in $region..."
        aws ecr get-login-password --region $region | \
            docker login --username AWS --password-stdin $REGISTRY 2>/dev/null
    else
        log_warn "Registry is not AWS ECR, skipping automatic authentication"
    fi
}

push_images() {
    if [ -z "$REGISTRY" ]; then
        log_error "Registry not specified. Use -r or --registry option."
        exit 1
    fi

    # Authenticate with ECR if needed
    ecr_login

    # Create repositories if they don't exist
    case $BUILD_TARGET in
        efa)
            create_ecr_repo ${EFA_IMAGE}${GPU_SUFFIX}
            ;;
        trtllm)
            create_ecr_repo ${TRTLLM_IMAGE}${GPU_SUFFIX}
            ;;
        vllm)
            create_ecr_repo ${VLLM_IMAGE}${GPU_SUFFIX}
            ;;
        all)
            create_ecr_repo ${EFA_IMAGE}${GPU_SUFFIX}
            create_ecr_repo ${TRTLLM_IMAGE}${GPU_SUFFIX}
            create_ecr_repo ${VLLM_IMAGE}${GPU_SUFFIX}
            ;;
    esac

    log_info "Pushing images to ${REGISTRY}..."

    case $BUILD_TARGET in
        efa)
            docker push ${REGISTRY}/${EFA_IMAGE}${GPU_SUFFIX}:${TAG} || log_error "Failed to push ${EFA_IMAGE}${GPU_SUFFIX}"
            log_info "✅ Pushed: ${REGISTRY}/${EFA_IMAGE}${GPU_SUFFIX}:${TAG}"
            ;;
        trtllm)
            docker push ${REGISTRY}/${TRTLLM_IMAGE}${GPU_SUFFIX}:${TAG} || log_error "Failed to push ${TRTLLM_IMAGE}${GPU_SUFFIX}"
            log_info "✅ Pushed: ${REGISTRY}/${TRTLLM_IMAGE}${GPU_SUFFIX}:${TAG}"
            ;;
        vllm)
            docker push ${REGISTRY}/${VLLM_IMAGE}${GPU_SUFFIX}:${TAG} || log_error "Failed to push ${VLLM_IMAGE}${GPU_SUFFIX}"
            log_info "✅ Pushed: ${REGISTRY}/${VLLM_IMAGE}${GPU_SUFFIX}:${TAG}"
            ;;
        all)
            docker push ${REGISTRY}/${EFA_IMAGE}${GPU_SUFFIX}:${TAG} || log_error "Failed to push ${EFA_IMAGE}${GPU_SUFFIX}"
            log_info "✅ Pushed: ${REGISTRY}/${EFA_IMAGE}${GPU_SUFFIX}:${TAG}"
            docker push ${REGISTRY}/${TRTLLM_IMAGE}${GPU_SUFFIX}:${TAG} || log_error "Failed to push ${TRTLLM_IMAGE}${GPU_SUFFIX}"
            log_info "✅ Pushed: ${REGISTRY}/${TRTLLM_IMAGE}${GPU_SUFFIX}:${TAG}"
            docker push ${REGISTRY}/${VLLM_IMAGE}${GPU_SUFFIX}:${TAG} || log_error "Failed to push ${VLLM_IMAGE}${GPU_SUFFIX}"
            log_info "✅ Pushed: ${REGISTRY}/${VLLM_IMAGE}${GPU_SUFFIX}:${TAG}"
            ;;
    esac

    log_info "Push completed successfully!"
}

# Function to check prerequisites
check_prerequisites() {
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check if AWS CLI is installed when pushing to ECR
    if [ "$PUSH" = true ] && [ -n "$REGISTRY" ]; then
        if [[ "$REGISTRY" == *"ecr.aws"* ]]; then
            if ! command -v aws &> /dev/null; then
                log_error "AWS CLI is not installed. Please install AWS CLI to push to ECR."
                exit 1
            fi

            # Check AWS credentials
            if ! aws sts get-caller-identity &> /dev/null; then
                log_error "AWS credentials not configured. Please run 'aws configure' or set AWS credentials."
                exit 1
            fi
        fi
    fi
}

# Main build logic
log_info "Dynamo Inference on AWS - Build Script"
log_info "Build target: ${BUILD_TARGET}"
log_info "Tag: ${TAG}"

# Check prerequisites
check_prerequisites

case $BUILD_TARGET in
    efa)
        build_efa
        ;;
    trtllm)
        build_trtllm
        ;;
    vllm)
        build_vllm
        ;;
    all)
        build_efa
        build_trtllm
        build_vllm
        ;;
    *)
        log_error "Invalid build target: ${BUILD_TARGET}"
        print_usage
        exit 1
        ;;
esac

if [ "$PUSH" = true ]; then
    push_images
fi

log_info "Build completed successfully!"
echo ""
echo "Built images:"
docker images | grep -E "(${EFA_IMAGE}|${TRTLLM_IMAGE}|${VLLM_IMAGE})" | head -10
