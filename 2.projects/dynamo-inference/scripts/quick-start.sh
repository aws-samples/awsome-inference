#!/bin/bash

# Quick Start Script for Dynamo Inference
# One-command deployment and testing
# Usage: HF_TOKEN=your_token ./quick-start.sh

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       Dynamo Inference - Quick Start${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Setup
echo "Step 1: Running setup..."
"${SCRIPT_DIR}/setup-all.sh"

# Step 2: Configure
echo ""
echo "Step 2: Configuring environment..."
"${SCRIPT_DIR}/configure-environment.sh"

# Step 3: Validate
echo ""
echo "Step 3: Validating deployment..."
"${SCRIPT_DIR}/validate-deployment.sh"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}       Quick Start Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Your environment is ready. Next steps:"
echo "1. Build Docker images: ./docker/build.sh"
echo "2. Deploy a model: ./scripts/deploy-dynamo-vllm.sh"
echo "3. Run benchmarks: ./benchmarks/vllm-genai-perf/master-benchmark.sh"
echo ""