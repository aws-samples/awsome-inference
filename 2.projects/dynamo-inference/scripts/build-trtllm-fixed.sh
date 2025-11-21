#!/bin/bash
# Build TensorRT-LLM container with fixed nixlbench ETCD library

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}     Building TensorRT-LLM with nixlbench Fix${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Configuration
DOCKER_DIR="/home/ubuntu/awsome-inference/2.projects/dynamo-inference/docker"
BASE_IMAGE="${DYNAMO_BASE_IMAGE:-dynamo-base:latest}"
CUDA_ARCH="${CUDA_ARCH:-86}"
CUDA_ARCH_NAME="${CUDA_ARCH_NAME:-A10G}"
BUILD_TARGET="${BUILD_TARGET:-slim}"
TAG="${TAG:-dynamo-trtllm:fixed-${BUILD_TARGET}-$(date +%Y%m%d)}"
ECR_REPO="${ECR_REPO:-058264135704.dkr.ecr.us-east-2.amazonaws.com}"

echo "Configuration:"
echo "  Base Image: ${BASE_IMAGE}"
echo "  CUDA Arch: ${CUDA_ARCH} (${CUDA_ARCH_NAME})"
echo "  Build Target: ${BUILD_TARGET}"
echo "  Tag: ${TAG}"
echo "  ECR Repo: ${ECR_REPO}"
echo ""

# Check if Dockerfile exists
if [ ! -f "${DOCKER_DIR}/Dockerfile.trtllm-fixed" ]; then
    echo -e "${RED}Error: Dockerfile.trtllm-fixed not found at ${DOCKER_DIR}${NC}"
    exit 1
fi

# Build the image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg CUDA_ARCH="${CUDA_ARCH}" \
    --build-arg CUDA_ARCH_NAME="${CUDA_ARCH_NAME}" \
    --build-arg BUILD_TARGET="${BUILD_TARGET}" \
    --build-arg TRTLLM_VERSION="${TRTLLM_VERSION:-v0.15.0}" \
    -t "${TAG}" \
    -f "${DOCKER_DIR}/Dockerfile.trtllm-fixed" \
    "${DOCKER_DIR}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo ""
    echo "Tagged as: ${TAG}"

    # Test the fix is present
    echo ""
    echo -e "${YELLOW}Verifying nixlbench fix...${NC}"
    docker run --rm ${TAG} bash -c "
        if strings /usr/local/lib/libetcd-cpp-api-core.so | grep -q ETCD_CPP_API_DISABLE_URI_VALIDATION; then
            echo '✅ Fix verified: ETCD_CPP_API_DISABLE_URI_VALIDATION found in library'
        else
            echo '❌ Warning: Fix not found in library'
        fi
        echo ''
        echo 'Environment variable set:'
        echo \"ETCD_CPP_API_DISABLE_URI_VALIDATION=\$ETCD_CPP_API_DISABLE_URI_VALIDATION\"
    "

    # Offer to push to ECR
    echo ""
    read -p "Push to ECR? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Pushing to ECR...${NC}"

        # Login to ECR
        aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin ${ECR_REPO}

        # Tag for ECR
        ECR_TAG="${ECR_REPO}/${TAG}"
        docker tag ${TAG} ${ECR_TAG}

        # Push
        docker push ${ECR_TAG}

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Pushed to ECR: ${ECR_TAG}${NC}"
        else
            echo -e "${RED}❌ Failed to push to ECR${NC}"
        fi
    fi
else
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "To use this image in Kubernetes:"
echo "  1. Update your pod spec to use: ${TAG}"
echo "  2. The ETCD_CPP_API_DISABLE_URI_VALIDATION=1 is set by default"
echo "  3. nixlbench should work without the URI validation error"
echo ""
echo "Test command:"
echo "  docker run --rm -it ${TAG} nixlbench --help"
echo ""