#!/bin/bash
# Apply nixlbench fix to existing dynamo-trtllm image

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}     Applying nixlbench Fix to Existing Image${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Default values
BASE_IMAGE="${1:-058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:all-arch}"
OUTPUT_TAG="${2:-dynamo-trtllm:all-arch-fixed}"
ECR_REPO="${ECR_REPO:-058264135704.dkr.ecr.us-east-2.amazonaws.com}"

echo "Configuration:"
echo "  Base Image: ${BASE_IMAGE}"
echo "  Output Tag: ${OUTPUT_TAG}"
echo ""

# Build the patched image
echo -e "${YELLOW}Building patched image...${NC}"
docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    -t "${OUTPUT_TAG}" \
    -f /home/ubuntu/awsome-inference/2.projects/dynamo-inference/docker/Dockerfile.nixlbench-patch \
    /home/ubuntu/awsome-inference/2.projects/dynamo-inference/docker/

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo ""

    # Test the fix
    echo -e "${YELLOW}Testing the fix...${NC}"
    docker run --rm ${OUTPUT_TAG} nixlbench-test

    # Offer to push
    echo ""
    read -p "Push to ECR? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Login to ECR
        aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin ${ECR_REPO}

        # Tag and push
        ECR_TAG="${ECR_REPO}/${OUTPUT_TAG}"
        docker tag ${OUTPUT_TAG} ${ECR_TAG}
        docker push ${ECR_TAG}

        echo -e "${GREEN}✅ Pushed to: ${ECR_TAG}${NC}"
    fi
else
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Patch Applied Successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "To use in Kubernetes:"
echo "  kubectl set image deployment/your-deployment your-container=${OUTPUT_TAG}"
echo ""
echo "The fix sets ETCD_CPP_API_DISABLE_URI_VALIDATION=1 by default"
echo "nixlbench should now work without the URI validation error"