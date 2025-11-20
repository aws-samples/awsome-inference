#!/usr/bin/env bash
# Modular build script for NIXL base and Dynamo images
#
# Usage:
#   ./build-modular.sh base          # Build only NIXL base
#   ./build-modular.sh dynamo        # Build only Dynamo (uses existing NIXL base)
#   ./build-modular.sh all           # Build both NIXL base and Dynamo
#   ./build-modular.sh trtllm        # Build TensorRT-LLM specifically
#   ./build-modular.sh vllm          # Build vLLM specifically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
BUILD_MODE="${1}"
NIXL_TAG="${NIXL_TAG:-nixl-aligned:0.7.1-nccl}"
DYNAMO_BASE_TAG="${DYNAMO_BASE_TAG:-dynamo-base:v0.6.1.dev.b573bc198}"
DYNAMO_BUILD_TARGET="${DYNAMO_BUILD_TARGET:-trtllm}"
DYNAMO_TARGET_STAGE="${DYNAMO_TARGET_STAGE:-slim}"
CUDA_ARCH="${CUDA_ARCH:-90}"
CUDA_ARCH_NAME="${CUDA_ARCH_NAME:-H100}"

# Usage
usage() {
    echo "Usage: $0 <mode> [options]"
    echo ""
    echo "Modes:"
    echo "  base          Build only NIXL base image with NCCL + aws-ofi-nccl"
    echo "  trtllm        Build TensorRT-LLM only (requires existing NIXL base)"
    echo "  vllm          Build vLLM only (requires existing NIXL base)"
    echo "  all-trtllm    Build NIXL base + TensorRT-LLM"
    echo "  all-vllm      Build NIXL base + vLLM"
    echo ""
    echo "Environment Variables:"
    echo "  NIXL_TAG                Tag for NIXL base image (default: $NIXL_TAG)"
    echo "  DYNAMO_BASE_TAG         Tag for Dynamo base image (default: $DYNAMO_BASE_TAG)"
    echo "  DYNAMO_BUILD_TARGET     What to build: trtllm or vllm (default: $DYNAMO_BUILD_TARGET)"
    echo "  DYNAMO_TARGET_STAGE     Build stage: slim, full, or runtime (default: $DYNAMO_TARGET_STAGE)"
    echo "  CUDA_ARCH               CUDA compute capability (default: $CUDA_ARCH)"
    echo "  CUDA_ARCH_NAME          GPU architecture name (default: $CUDA_ARCH_NAME)"
    echo ""
    echo "Examples:"
    echo "  # Build just the NIXL base with NCCL"
    echo "  ./build-modular.sh base"
    echo ""
    echo "  # Build TensorRT-LLM only (requires existing NIXL base)"
    echo "  NIXL_TAG=nixl-aligned:0.7.1-nccl ./build-modular.sh trtllm"
    echo ""
    echo "  # Build NIXL base + TensorRT-LLM together"
    echo "  ./build-modular.sh all-trtllm"
    echo ""
    echo "  # Build NIXL base + vLLM together"
    echo "  ./build-modular.sh all-vllm"
    echo ""
    echo "  # Build vLLM with specific GPU arch"
    echo "  CUDA_ARCH=86 CUDA_ARCH_NAME=A10G ./build-modular.sh vllm"
    exit 1
}

# Print configuration
print_config() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    Modular Build Configuration${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "  Mode:               ${GREEN}${BUILD_MODE}${NC}"
    if [[ "$BUILD_MODE" != "base" ]]; then
        echo -e "  Build Target:       ${GREEN}${DYNAMO_BUILD_TARGET}${NC}"
        echo -e "  Target Stage:       ${GREEN}${DYNAMO_TARGET_STAGE}${NC}"
        echo -e "  NIXL Base:          ${GREEN}${NIXL_TAG}${NC}"
        echo -e "  Dynamo Base:        ${GREEN}${DYNAMO_BASE_TAG}${NC}"
        echo -e "  GPU Arch:           ${GREEN}SM${CUDA_ARCH} (${CUDA_ARCH_NAME})${NC}"
    else
        echo -e "  NIXL Tag:           ${GREEN}${NIXL_TAG}${NC}"
    fi
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

# Build NIXL base
build_nixl_base() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Building NIXL Base Image${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    cd "${SCRIPT_DIR}/nixl-aligned"

    if [ ! -f "build-nixl-aligned.sh" ]; then
        echo -e "${RED}✗ build-nixl-aligned.sh not found${NC}"
        exit 1
    fi

    # Check if script accepts TAG parameter, otherwise build and tag afterward
    if grep -q "TAG=" "build-nixl-aligned.sh"; then
        echo -e "${BLUE}Building with TAG=${NIXL_TAG}...${NC}"
        NON_INTERACTIVE=1 INSTALL_NCCL=1 TAG="${NIXL_TAG}" ./build-nixl-aligned.sh
    else
        echo -e "${BLUE}Building NIXL base...${NC}"
        NON_INTERACTIVE=1 INSTALL_NCCL=1 ./build-nixl-aligned.sh

        # Try to detect what the default tag was and retag it
        DEFAULT_TAG=$(grep -oP 'TAG="\K[^"]+' build-nixl-aligned.sh | head -1 || echo "nixl-aligned:0.7.1-bench")
        if [ "$DEFAULT_TAG" != "$NIXL_TAG" ]; then
            echo -e "${YELLOW}Retagging ${DEFAULT_TAG} -> ${NIXL_TAG}${NC}"
            docker tag "$DEFAULT_TAG" "$NIXL_TAG"
        fi
    fi

    echo ""
    echo -e "${GREEN}✓ NIXL base image built: ${NIXL_TAG}${NC}"
    echo ""
}

# Build Dynamo (TensorRT-LLM or vLLM)
build_dynamo() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Building Dynamo ${DYNAMO_BUILD_TARGET^^}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    cd "${SCRIPT_DIR}"

    # Check if NIXL base exists
    if ! docker image inspect "$NIXL_TAG" >/dev/null 2>&1; then
        echo -e "${RED}✗ NIXL base image not found: ${NIXL_TAG}${NC}"
        echo -e "${YELLOW}  Please build the NIXL base first or specify an existing one${NC}"
        echo -e "${YELLOW}  Example: NIXL_TAG=your-nixl-image:tag ./build-modular.sh dynamo${NC}"
        exit 1
    fi

    # Select the appropriate build script
    if [[ "$DYNAMO_BUILD_TARGET" == "trtllm" ]]; then
        BUILD_SCRIPT="./build_trtllm.sh"
    elif [[ "$DYNAMO_BUILD_TARGET" == "vllm" ]]; then
        BUILD_SCRIPT="./build_vllm.sh"
    else
        echo -e "${RED}✗ Unknown build target: ${DYNAMO_BUILD_TARGET}${NC}"
        echo -e "${YELLOW}  Valid targets: trtllm, vllm${NC}"
        exit 1
    fi

    if [ ! -f "$BUILD_SCRIPT" ]; then
        echo -e "${RED}✗ Build script not found: ${BUILD_SCRIPT}${NC}"
        exit 1
    fi

    # Export environment variables for the build script
    export NIXL_BASE_IMAGE="$NIXL_TAG"
    export DYNAMO_BASE_IMAGE="$DYNAMO_BASE_TAG"
    export BUILD_TARGET="$DYNAMO_TARGET_STAGE"
    export CUDA_ARCH="$CUDA_ARCH"
    export CUDA_ARCH_NAME="$CUDA_ARCH_NAME"
    export NON_INTERACTIVE="1"

    echo -e "${BLUE}Running: ${BUILD_SCRIPT}${NC}"
    "$BUILD_SCRIPT"

    echo ""
    echo -e "${GREEN}✓ Dynamo ${DYNAMO_BUILD_TARGET} image built${NC}"
    echo ""
}

# Main logic
main() {
    case "$BUILD_MODE" in
        base)
            print_config
            build_nixl_base
            echo -e "${GREEN}✓ Base build complete!${NC}"
            ;;
        trtllm)
            DYNAMO_BUILD_TARGET="trtllm"
            print_config
            build_dynamo
            echo -e "${GREEN}✓ TensorRT-LLM build complete!${NC}"
            ;;
        vllm)
            DYNAMO_BUILD_TARGET="vllm"
            print_config
            build_dynamo
            echo -e "${GREEN}✓ vLLM build complete!${NC}"
            ;;
        all-trtllm)
            DYNAMO_BUILD_TARGET="trtllm"
            print_config
            build_nixl_base
            build_dynamo
            echo -e "${GREEN}✓ All builds complete (Base + TensorRT-LLM)!${NC}"
            ;;
        all-vllm)
            DYNAMO_BUILD_TARGET="vllm"
            print_config
            build_nixl_base
            build_dynamo
            echo -e "${GREEN}✓ All builds complete (Base + vLLM)!${NC}"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            echo -e "${RED}✗ Unknown mode: ${BUILD_MODE}${NC}"
            echo ""
            usage
            ;;
    esac

    # Summary
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    Build Summary${NC}"
    echo -e "${BLUE}=========================================${NC}"
    if [[ "$BUILD_MODE" == "base" ]] || [[ "$BUILD_MODE" == "all-trtllm" ]] || [[ "$BUILD_MODE" == "all-vllm" ]]; then
        echo -e "  NIXL Base:          ${GREEN}${NIXL_TAG}${NC}"
    fi
    if [[ "$BUILD_MODE" != "base" ]]; then
        echo -e "  Dynamo:             ${GREEN}Built ${DYNAMO_BUILD_TARGET} (${DYNAMO_TARGET_STAGE})${NC}"
    fi
    echo -e "${BLUE}=========================================${NC}"
}

# Run main
main
