#!/bin/bash
#
# build-dynamo.sh - Configurable Docker build script for Dynamo
#
# Usage:
#   ./build-dynamo.sh                    # Build with defaults
#   ./build-dynamo.sh --arch arm64       # Build for ARM
#   ./build-dynamo.sh --config my.conf   # Use custom config
#   ./build-dynamo.sh --dry-run          # Show what would run
#

set -euo pipefail

##############################
# Default Configuration
##############################

# Architecture (auto-detect or override)
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
    x86_64)  ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    arm64)   ARCH="aarch64" ;;
    *)       echo "⚠️  Unknown arch: $ARCH, defaulting to x86_64"; ARCH="x86_64" ;;
esac

# Build parallelism
NPROC="${NPROC:-$(nproc)}"

# Versions
DEFAULT_PYTHON_VERSION="${DEFAULT_PYTHON_VERSION:-3.12}"
NIXL_VERSION="${NIXL_VERSION:-0.7.1}"
NIXL_GIT_TAG="${NIXL_GIT_TAG:-${NIXL_VERSION}}"
DYNAMO_GIT_TAG="${DYNAMO_GIT_TAG:-main}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-1.86.0}"

# Base image
BASE_IMAGE="${BASE_IMAGE:-aws-efa-base:latest}"

# Output image
IMAGE_NAME="${IMAGE_NAME:-dynamo}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

##############################
# Path Configuration
##############################

# CUDA
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"

# AWS/EFA paths
EFA_PREFIX="${EFA_PREFIX:-/opt/amazon/efa}"
GDRCOPY_PREFIX="${GDRCOPY_PREFIX:-/opt/gdrcopy}"
AWS_OFI_NCCL_PREFIX="${AWS_OFI_NCCL_PREFIX:-/opt/aws-ofi-nccl}"

# UCX/libfabric
UCX_PREFIX="${UCX_PREFIX:-/usr/local/ucx}"
LIBFABRIC_PREFIX="${LIBFABRIC_PREFIX:-/usr/local}"

# NIXL paths
NIXL_PREFIX="${NIXL_PREFIX:-/usr/local/nixl}"
NIXL_LIB_DIR="${NIXL_LIB_DIR:-${NIXL_PREFIX}/lib/${ARCH}-linux-gnu}"
NIXL_PLUGIN_DIR="${NIXL_PLUGIN_DIR:-${NIXL_LIB_DIR}/plugins}"
NIXL_BUILD_DIR="${NIXL_BUILD_DIR:-/workspace/nixl}"

# Python paths
PYTHON_SITE_PACKAGES="${PYTHON_SITE_PACKAGES:-/usr/local/lib/python${DEFAULT_PYTHON_VERSION}/dist-packages}"
TORCH_LIB_DIR="${TORCH_LIB_DIR:-${PYTHON_SITE_PACKAGES}/torch/lib}"
TENSORRT_LLM_DIR="${TENSORRT_LLM_DIR:-${PYTHON_SITE_PACKAGES}/tensorrt_llm}"
TENSORRT_LLM_LIBS="${TENSORRT_LLM_LIBS:-${TENSORRT_LLM_DIR}/libs}"
TENSORRT_DIR="${TENSORRT_DIR:-${PYTHON_SITE_PACKAGES}/tensorrt}"

# Application paths
DYNAMO_HOME="${DYNAMO_HOME:-/opt/dynamo}"

# Rust paths
RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"

##############################
# Docker build options
##############################
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
DOCKER_CONTEXT="${DOCKER_CONTEXT:-.}"
DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"
DOCKER_PROGRESS="${DOCKER_PROGRESS:-plain}"
NO_CACHE="${NO_CACHE:-0}"
PUSH="${PUSH:-0}"

##############################
# Parse command line arguments
##############################
DRY_RUN=0
CONFIG_FILE=""
SHOW_CONFIG=0
GENERATE_CONFIG=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --nproc)
            NPROC="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --dockerfile)
            DOCKERFILE="$2"
            shift 2
            ;;
        --image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --base)
            BASE_IMAGE="$2"
            shift 2
            ;;
        --dynamo-tag)
            DYNAMO_GIT_TAG="$2"
            shift 2
            ;;
        --nixl-version)
            NIXL_VERSION="$2"
            NIXL_GIT_TAG="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE=1
            shift
            ;;
        --push)
            PUSH=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --show-config)
            SHOW_CONFIG=1
            shift
            ;;
        --generate-config)
            GENERATE_CONFIG=1
            shift
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Build Options:
  --arch ARCH           Architecture (x86_64, aarch64) [auto-detected: $ARCH]
  --nproc N             Number of parallel jobs [default: $(nproc)]
  --dockerfile FILE     Dockerfile to use [default: Dockerfile]
  --image NAME          Output image name [default: dynamo]
  --tag TAG             Output image tag [default: latest]
  --base IMAGE          Base image [default: aws-efa-base:latest]
  --no-cache            Build without cache
  --push                Push image after build

Version Options:
  --dynamo-tag TAG      Dynamo git tag/branch [default: main]
  --nixl-version VER    NIXL version [default: 0.7.1]

Configuration:
  --config FILE         Load configuration from file
  --show-config         Show current configuration and exit
  --generate-config     Generate config file template and exit

Other:
  --dry-run             Show docker command without executing
  --help                Show this help

Examples:
  $0                                    # Build with defaults
  $0 --arch aarch64                     # Build for ARM64
  $0 --dynamo-tag v0.2.0 --tag v0.2.0   # Build specific version
  $0 --config prod.conf --push          # Use config file and push
  $0 --generate-config > my.conf        # Create config template
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

##############################
# Load config file if specified
##############################
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    echo "📄 Loading config from: $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

# Recalculate derived paths after config load
NIXL_LIB_DIR="${NIXL_LIB_DIR:-${NIXL_PREFIX}/lib/${ARCH}-linux-gnu}"
NIXL_PLUGIN_DIR="${NIXL_PLUGIN_DIR:-${NIXL_LIB_DIR}/plugins}"
PYTHON_SITE_PACKAGES="${PYTHON_SITE_PACKAGES:-/usr/local/lib/python${DEFAULT_PYTHON_VERSION}/dist-packages}"
TORCH_LIB_DIR="${TORCH_LIB_DIR:-${PYTHON_SITE_PACKAGES}/torch/lib}"
TENSORRT_LLM_DIR="${TENSORRT_LLM_DIR:-${PYTHON_SITE_PACKAGES}/tensorrt_llm}"
TENSORRT_LLM_LIBS="${TENSORRT_LLM_LIBS:-${TENSORRT_LLM_DIR}/libs}"
TENSORRT_DIR="${TENSORRT_DIR:-${PYTHON_SITE_PACKAGES}/tensorrt}"

##############################
# Generate config file
##############################
if [[ "$GENERATE_CONFIG" -eq 1 ]]; then
    cat <<EOF
# Dynamo Docker Build Configuration
# Generated: $(date)
# Usage: ./build-dynamo.sh --config this-file.conf

##############################
# Architecture
##############################
ARCH="${ARCH}"
NPROC="${NPROC}"

##############################
# Versions
##############################
DEFAULT_PYTHON_VERSION="${DEFAULT_PYTHON_VERSION}"
NIXL_VERSION="${NIXL_VERSION}"
NIXL_GIT_TAG="${NIXL_GIT_TAG}"
DYNAMO_GIT_TAG="${DYNAMO_GIT_TAG}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN}"

##############################
# Images
##############################
BASE_IMAGE="${BASE_IMAGE}"
IMAGE_NAME="${IMAGE_NAME}"
IMAGE_TAG="${IMAGE_TAG}"

##############################
# CUDA Paths
##############################
CUDA_HOME="${CUDA_HOME}"

##############################
# AWS/EFA Paths
##############################
EFA_PREFIX="${EFA_PREFIX}"
GDRCOPY_PREFIX="${GDRCOPY_PREFIX}"
AWS_OFI_NCCL_PREFIX="${AWS_OFI_NCCL_PREFIX}"

##############################
# UCX/libfabric Paths
##############################
UCX_PREFIX="${UCX_PREFIX}"
LIBFABRIC_PREFIX="${LIBFABRIC_PREFIX}"

##############################
# NIXL Paths
##############################
NIXL_PREFIX="${NIXL_PREFIX}"
NIXL_LIB_DIR="${NIXL_LIB_DIR}"
NIXL_PLUGIN_DIR="${NIXL_PLUGIN_DIR}"
NIXL_BUILD_DIR="${NIXL_BUILD_DIR}"

##############################
# Python Paths
##############################
PYTHON_SITE_PACKAGES="${PYTHON_SITE_PACKAGES}"
TORCH_LIB_DIR="${TORCH_LIB_DIR}"
TENSORRT_LLM_DIR="${TENSORRT_LLM_DIR}"
TENSORRT_LLM_LIBS="${TENSORRT_LLM_LIBS}"
TENSORRT_DIR="${TENSORRT_DIR}"

##############################
# Application Paths
##############################
DYNAMO_HOME="${DYNAMO_HOME}"

##############################
# Rust Paths
##############################
RUSTUP_HOME="${RUSTUP_HOME}"
CARGO_HOME="${CARGO_HOME}"

##############################
# Docker Options
##############################
DOCKERFILE="${DOCKERFILE}"
DOCKER_CONTEXT="${DOCKER_CONTEXT}"
NO_CACHE="${NO_CACHE}"
PUSH="${PUSH}"
EOF
    exit 0
fi

##############################
# Show configuration
##############################
show_config() {
    cat <<EOF
==============================
 Dynamo Build Configuration
==============================

Architecture:
  ARCH                  = ${ARCH}
  NPROC                 = ${NPROC}

Versions:
  PYTHON_VERSION        = ${DEFAULT_PYTHON_VERSION}
  NIXL_VERSION          = ${NIXL_VERSION}
  DYNAMO_GIT_TAG        = ${DYNAMO_GIT_TAG}
  RUST_TOOLCHAIN        = ${RUST_TOOLCHAIN}

Images:
  BASE_IMAGE            = ${BASE_IMAGE}
  OUTPUT                = ${IMAGE_NAME}:${IMAGE_TAG}

Paths (CUDA/AWS):
  CUDA_HOME             = ${CUDA_HOME}
  EFA_PREFIX            = ${EFA_PREFIX}
  GDRCOPY_PREFIX        = ${GDRCOPY_PREFIX}
  AWS_OFI_NCCL_PREFIX   = ${AWS_OFI_NCCL_PREFIX}
  UCX_PREFIX            = ${UCX_PREFIX}
  LIBFABRIC_PREFIX      = ${LIBFABRIC_PREFIX}

Paths (NIXL):
  NIXL_PREFIX           = ${NIXL_PREFIX}
  NIXL_LIB_DIR          = ${NIXL_LIB_DIR}
  NIXL_PLUGIN_DIR       = ${NIXL_PLUGIN_DIR}

Paths (Python):
  PYTHON_SITE_PACKAGES  = ${PYTHON_SITE_PACKAGES}
  TORCH_LIB_DIR         = ${TORCH_LIB_DIR}
  TENSORRT_LLM_DIR      = ${TENSORRT_LLM_DIR}

Paths (Application):
  DYNAMO_HOME           = ${DYNAMO_HOME}
  RUSTUP_HOME           = ${RUSTUP_HOME}
  CARGO_HOME            = ${CARGO_HOME}

Docker:
  DOCKERFILE            = ${DOCKERFILE}
  NO_CACHE              = ${NO_CACHE}
  PUSH                  = ${PUSH}

==============================
EOF
}

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
    show_config
    exit 0
fi

##############################
# Build Docker command
##############################
BUILD_ARGS=(
    # Architecture
    --build-arg "ARCH=${ARCH}"
    --build-arg "NPROC=${NPROC}"
    
    # Versions
    --build-arg "DEFAULT_PYTHON_VERSION=${DEFAULT_PYTHON_VERSION}"
    --build-arg "NIXL_VERSION=${NIXL_VERSION}"
    --build-arg "NIXL_GIT_TAG=${NIXL_GIT_TAG}"
    --build-arg "DYNAMO_GIT_TAG=${DYNAMO_GIT_TAG}"
    --build-arg "RUST_TOOLCHAIN=${RUST_TOOLCHAIN}"
    
    # CUDA/AWS paths
    --build-arg "CUDA_HOME=${CUDA_HOME}"
    --build-arg "EFA_PREFIX=${EFA_PREFIX}"
    --build-arg "GDRCOPY_PREFIX=${GDRCOPY_PREFIX}"
    --build-arg "AWS_OFI_NCCL_PREFIX=${AWS_OFI_NCCL_PREFIX}"
    --build-arg "UCX_PREFIX=${UCX_PREFIX}"
    --build-arg "LIBFABRIC_PREFIX=${LIBFABRIC_PREFIX}"
    
    # NIXL paths
    --build-arg "NIXL_PREFIX=${NIXL_PREFIX}"
    --build-arg "NIXL_LIB_DIR=${NIXL_LIB_DIR}"
    --build-arg "NIXL_PLUGIN_DIR=${NIXL_PLUGIN_DIR}"
    --build-arg "NIXL_BUILD_DIR=${NIXL_BUILD_DIR}"
    
    # Python paths
    --build-arg "PYTHON_SITE_PACKAGES=${PYTHON_SITE_PACKAGES}"
    --build-arg "TORCH_LIB_DIR=${TORCH_LIB_DIR}"
    --build-arg "TENSORRT_LLM_DIR=${TENSORRT_LLM_DIR}"
    --build-arg "TENSORRT_LLM_LIBS=${TENSORRT_LLM_LIBS}"
    --build-arg "TENSORRT_DIR=${TENSORRT_DIR}"
    
    # Application paths
    --build-arg "DYNAMO_HOME=${DYNAMO_HOME}"
    --build-arg "RUSTUP_HOME=${RUSTUP_HOME}"
    --build-arg "CARGO_HOME=${CARGO_HOME}"
)

DOCKER_OPTS=(
    --progress="${DOCKER_PROGRESS}"
    -f "${DOCKERFILE}"
    -t "${IMAGE_NAME}:${IMAGE_TAG}"
)

if [[ "$NO_CACHE" -eq 1 ]]; then
    DOCKER_OPTS+=(--no-cache)
fi

# Full command
DOCKER_CMD="DOCKER_BUILDKIT=${DOCKER_BUILDKIT} docker build ${DOCKER_OPTS[*]} ${BUILD_ARGS[*]} ${DOCKER_CONTEXT}"

##############################
# Execute
##############################
echo ""
show_config
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "🔍 Dry run - would execute:"
    echo ""
    echo "$DOCKER_CMD"
    echo ""
    exit 0
fi

echo "🚀 Starting build..."
echo ""

eval "$DOCKER_CMD"

BUILD_STATUS=$?

if [[ $BUILD_STATUS -eq 0 ]]; then
    echo ""
    echo "✅ Build successful: ${IMAGE_NAME}:${IMAGE_TAG}"
    
    if [[ "$PUSH" -eq 1 ]]; then
        echo "📤 Pushing image..."
        docker push "${IMAGE_NAME}:${IMAGE_TAG}"
    fi
    
    echo ""
    echo "Test with:"
    echo "  docker run --rm --gpus all ${IMAGE_NAME}:${IMAGE_TAG} python3 -c \\"
    echo "    'from tensorrt_llm.bindings import executor; print(\"OK\")'"
else
    echo ""
    echo "❌ Build failed with exit code: $BUILD_STATUS"
    exit $BUILD_STATUS
fi