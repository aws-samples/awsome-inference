#!/bin/bash
# rebuild-fixed-a10g-images.sh - Rebuild A10G images with VIRTUAL_ENV fix
#
# This script rebuilds the dynamo-vllm-efa:slim-a10g and dynamo-trtllm-efa:slim-a10g
# images with the fix for the VIRTUAL_ENV ordering bug that caused
# "ModuleNotFoundError: No module named 'dynamo'"

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Rebuilding Fixed A10G Slim Images${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}This script will:${NC}"
echo "  1. Build dynamo-vllm-efa:slim-a10g with VIRTUAL_ENV fix"
echo "  2. Build dynamo-trtllm-efa:slim-a10g with VIRTUAL_ENV fix"
echo "  3. Run validation tests to ensure dynamo modules work"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  GPU Architecture: A10G (SM 86)"
echo "  Build Target: slim (debloated)"
echo "  Base Image: nixl-h100-efa:optimized"
echo ""
echo -e "${YELLOW}Fix Applied:${NC}"
echo "  - VIRTUAL_ENV now defined BEFORE using it in PATH"
echo "  - Fixes: ModuleNotFoundError: No module named 'dynamo'"
echo ""

# Check if base image exists
if ! docker images | grep -q "nixl-h100-efa.*optimized"; then
    echo -e "${RED}ERROR: Base image nixl-h100-efa:optimized not found!${NC}"
    echo ""
    echo "Please build the base image first:"
    echo "  docker build -f Dockerfile.base -t nixl-h100-efa:optimized ."
    echo ""
    exit 1
fi

echo -e "${GREEN}Base image found: nixl-h100-efa:optimized${NC}"
echo ""

# Confirmation
read -p "Proceed with rebuild? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

START_TIME=$(date +%s)

# Build vLLM
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 1/2: Building dynamo-vllm-efa:slim-a10g${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

NIXL_BASE_IMAGE=nixl-h100-efa:optimized \
BUILD_TARGET=slim \
CUDA_ARCH=86 \
CUDA_ARCH_NAME=A10G \
TAG=dynamo-vllm-efa:slim-a10g \
./build_vllm.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ vLLM build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ vLLM image built successfully${NC}"
echo ""

# Build TensorRT-LLM
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2/2: Building dynamo-trtllm-efa:slim-a10g${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

NIXL_BASE_IMAGE=nixl-h100-efa:optimized \
BUILD_TARGET=slim \
CUDA_ARCH=86 \
CUDA_ARCH_NAME=A10G \
TAG=dynamo-trtllm-efa:slim-a10g \
./build_trtllm.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ TensorRT-LLM build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ TensorRT-LLM image built successfully${NC}"
echo ""

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))
BUILD_MINUTES=$((BUILD_DURATION / 60))
BUILD_SECONDS=$((BUILD_DURATION % 60))

# Run validation
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Running Validation Tests${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -x ./scripts/test-dynamo-modules.sh ]; then
    ./scripts/test-dynamo-modules.sh
    VALIDATION_RESULT=$?
else
    echo -e "${YELLOW}⚠ Validation script not found, running manual tests...${NC}"
    echo ""

    # Manual validation
    echo "Testing dynamo-vllm-efa:slim-a10g..."
    if docker run --rm --entrypoint python dynamo-vllm-efa:slim-a10g -c "import dynamo.vllm; print('✓ dynamo.vllm works')" 2>&1 | grep -q "✓"; then
        echo -e "${GREEN}✓ dynamo-vllm-efa:slim-a10g validated${NC}"
    else
        echo -e "${RED}✗ dynamo-vllm-efa:slim-a10g validation failed${NC}"
        VALIDATION_RESULT=1
    fi

    echo ""
    echo "Testing dynamo-trtllm-efa:slim-a10g..."
    if docker run --rm --entrypoint python dynamo-trtllm-efa:slim-a10g -c "import dynamo.trtllm; print('✓ dynamo.trtllm works')" 2>&1 | grep -q "✓"; then
        echo -e "${GREEN}✓ dynamo-trtllm-efa:slim-a10g validated${NC}"
        VALIDATION_RESULT=0
    else
        echo -e "${RED}✗ dynamo-trtllm-efa:slim-a10g validation failed${NC}"
        VALIDATION_RESULT=1
    fi
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"

if [ $VALIDATION_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ BUILD AND VALIDATION SUCCESSFUL${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}Images built:${NC}"
    echo "  1. dynamo-vllm-efa:slim-a10g"
    echo "  2. dynamo-trtllm-efa:slim-a10g"
    echo ""
    echo "Build time: ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo ""
    echo "  # Test vLLM module"
    echo "  docker run --rm dynamo-vllm-efa:slim-a10g python -m dynamo.vllm --help"
    echo ""
    echo "  # Test TensorRT-LLM module"
    echo "  docker run --rm dynamo-trtllm-efa:slim-a10g python -m dynamo.trtllm --help"
    echo ""
    echo "  # Run with GPU"
    echo "  docker run -it --gpus all --network host dynamo-vllm-efa:slim-a10g"
    echo ""
    echo "  # Tag for publishing (update registry as needed)"
    echo "  docker tag dynamo-vllm-efa:slim-a10g <registry>/dynamo-vllm-efa:slim-a10g"
    echo "  docker tag dynamo-trtllm-efa:slim-a10g <registry>/dynamo-trtllm-efa:slim-a10g"
    echo ""
    echo "  # Push to registry"
    echo "  docker push <registry>/dynamo-vllm-efa:slim-a10g"
    echo "  docker push <registry>/dynamo-trtllm-efa:slim-a10g"
    echo ""
    exit 0
else
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "The images were built but validation tests failed."
    echo "Please check the error messages above and review:"
    echo ""
    echo "  1. BUGFIX_DYNAMO_MODULE_2025-11-17.md for details"
    echo "  2. Dockerfile.dynamo-vllm and Dockerfile.dynamo-trtllm"
    echo "  3. Build logs for any error messages"
    echo ""
    exit 1
fi
