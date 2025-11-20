#!/bin/bash
# Push Dynamo and NIXL containers to ECR with auto-detection
# Automatically detects AWS account ID and region

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    ECR Push Script - Auto-detect Account & Region${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Auto-detect AWS account ID
echo -e "${YELLOW}Detecting AWS configuration...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}✗ Failed to detect AWS Account ID${NC}"
    echo "  Please configure AWS CLI: aws configure"
    exit 1
fi
echo -e "${GREEN}✓ AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"

# Auto-detect AWS region
AWS_REGION=$(aws configure get region 2>/dev/null)
if [ -z "$AWS_REGION" ]; then
    # Try to get from EC2 metadata if running on EC2
    echo "  Checking EC2 metadata for region..."
    AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)
fi
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}⚠ Could not auto-detect region, using default: us-east-2${NC}"
    AWS_REGION="us-east-2"
fi
echo -e "${GREEN}✓ AWS Region: ${AWS_REGION}${NC}"

# ECR Registry URL
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo -e "${GREEN}✓ ECR Registry: ${ECR_REGISTRY}${NC}"
echo ""

# Define images to push (local:remote mapping)
declare -A IMAGES=(
    ["dynamo-trtllm:latest"]="dynamo-trtllm:latest"
    ["nixl-aligned:0.7.1-nccl"]="nixl-aligned:0.7.1-nccl"
)

# Optional: Add more images if they exist
if docker image inspect "dynamo-vllm:latest" >/dev/null 2>&1; then
    IMAGES["dynamo-vllm:latest"]="dynamo-vllm:latest"
fi
if docker image inspect "dynamo-base:latest" >/dev/null 2>&1; then
    IMAGES["dynamo-base:latest"]="dynamo-base:latest"
fi

# Login to ECR
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Logging into ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ ECR login failed${NC}"
    echo "  Please check your AWS credentials and permissions"
    exit 1
fi
echo -e "${GREEN}✓ ECR login successful${NC}"
echo ""

# Process each image
PUSHED_IMAGES=()
FAILED_IMAGES=()

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Processing Images${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for LOCAL_IMAGE in "${!IMAGES[@]}"; do
    REMOTE_TAG="${IMAGES[$LOCAL_IMAGE]}"
    REPO_NAME="${REMOTE_TAG%%:*}"  # Extract repo name (before :)

    echo ""
    echo -e "${BLUE}Processing: ${LOCAL_IMAGE}${NC}"
    echo -e "${BLUE}───────────────────────────────────${NC}"

    # Check if local image exists
    if ! docker image inspect "$LOCAL_IMAGE" >/dev/null 2>&1; then
        echo -e "${RED}  ✗ Local image not found: ${LOCAL_IMAGE}${NC}"
        echo -e "${YELLOW}  Skipping...${NC}"
        FAILED_IMAGES+=("${LOCAL_IMAGE} (not found locally)")
        continue
    fi

    # Get image size
    IMAGE_SIZE=$(docker image inspect "$LOCAL_IMAGE" --format='{{.Size}}' | numfmt --to=iec-i --suffix=B)
    echo -e "  Image size: ${IMAGE_SIZE}"

    # Create ECR repository if it doesn't exist
    echo "  Checking ECR repository..."
    aws ecr describe-repositories --repository-names ${REPO_NAME} --region ${AWS_REGION} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "  Creating new repository..."
        aws ecr create-repository \
            --repository-name ${REPO_NAME} \
            --region ${AWS_REGION} \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256 \
            >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ Created repository: ${REPO_NAME}${NC}"
        else
            echo -e "${RED}  ✗ Failed to create repository: ${REPO_NAME}${NC}"
            FAILED_IMAGES+=("${LOCAL_IMAGE} (repo creation failed)")
            continue
        fi
    else
        echo -e "${GREEN}  ✓ Repository exists: ${REPO_NAME}${NC}"
    fi

    # Tag image for ECR
    FULL_ECR_TAG="${ECR_REGISTRY}/${REMOTE_TAG}"
    echo "  Tagging image for ECR..."
    docker tag ${LOCAL_IMAGE} ${FULL_ECR_TAG}
    echo -e "${GREEN}  ✓ Tagged as: ${FULL_ECR_TAG}${NC}"

    # Push to ECR
    echo -e "${YELLOW}  Pushing to ECR (this may take a few minutes)...${NC}"
    docker push ${FULL_ECR_TAG}
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Successfully pushed: ${FULL_ECR_TAG}${NC}"
        PUSHED_IMAGES+=("${FULL_ECR_TAG}")
    else
        echo -e "${RED}  ✗ Failed to push: ${FULL_ECR_TAG}${NC}"
        FAILED_IMAGES+=("${LOCAL_IMAGE} (push failed)")
    fi
done

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Summary${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ ${#PUSHED_IMAGES[@]} -gt 0 ]; then
    echo -e "${GREEN}✓ Successfully pushed images:${NC}"
    for img in "${PUSHED_IMAGES[@]}"; do
        echo "  - $img"
    done
fi

if [ ${#FAILED_IMAGES[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}✗ Failed images:${NC}"
    for img in "${FAILED_IMAGES[@]}"; do
        echo "  - $img"
    done
fi

# Generate updated YAML commands
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Next Steps: Update Kubernetes YAMLs${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "# 1. Update NIXL benchmark deployment:"
echo "sed -i 's|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g' ${SCRIPT_DIR}/examples/nixl-benchmark-deployment.yaml"
echo "sed -i 's|us-east-2|${AWS_REGION}|g' ${SCRIPT_DIR}/examples/nixl-benchmark-deployment.yaml"
echo ""

echo "# 2. Update TRT-LLM deployment:"
echo "sed -i 's|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g' ${SCRIPT_DIR}/deployments/trtllm/trtllm-disagg-qwen.yaml"
echo "sed -i 's|us-east-2|${AWS_REGION}|g' ${SCRIPT_DIR}/deployments/trtllm/trtllm-disagg-qwen.yaml"
echo ""

echo "# 3. Update vLLM test pod (if exists):"
echo "sed -i 's|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g' ${SCRIPT_DIR}/examples/vllm-test-pod.yaml"
echo "sed -i 's|us-east-2|${AWS_REGION}|g' ${SCRIPT_DIR}/examples/vllm-test-pod.yaml"
echo ""

echo -e "${GREEN}Ready to use these images in your YAMLs:${NC}"
echo "  NIXL Image: ${ECR_REGISTRY}/nixl-aligned:0.7.1-nccl"
echo "  TRT-LLM Image: ${ECR_REGISTRY}/dynamo-trtllm:latest"
if [ -n "${IMAGES[dynamo-vllm:latest]}" ]; then
    echo "  vLLM Image: ${ECR_REGISTRY}/dynamo-vllm:latest"
fi
if [ -n "${IMAGES[dynamo-base:latest]}" ]; then
    echo "  Base Image: ${ECR_REGISTRY}/dynamo-base:latest"
fi
echo ""

# Create a quick deploy script
cat > ${SCRIPT_DIR}/quick-deploy.sh << EOF
#!/bin/bash
# Quick deploy script with updated ECR images
# Generated by push-to-ecr.sh on $(date)

ECR_REGISTRY="${ECR_REGISTRY}"
AWS_REGION="${AWS_REGION}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"

echo "Deploying with ECR images from \${ECR_REGISTRY}"

# Update and apply NIXL benchmark
sed -i "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" examples/nixl-benchmark-deployment.yaml
sed -i "s|nixl-aligned:.*|nixl-aligned:0.7.1-nccl|g" examples/nixl-benchmark-deployment.yaml
kubectl apply -f examples/nixl-benchmark-deployment.yaml

echo "✓ Deployment complete!"
echo "Check status with: kubectl get pods -l app=nixl-benchmark"
EOF

chmod +x ${SCRIPT_DIR}/quick-deploy.sh
echo -e "${GREEN}✓ Created quick-deploy.sh for easy deployment${NC}"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ ECR push complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"