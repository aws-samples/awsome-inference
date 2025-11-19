#!/bin/bash
# test-dynamo-modules.sh - Validate dynamo module installation in container images
#
# This script tests that the dynamo.vllm and dynamo.trtllm modules are properly
# installed and accessible in the built container images.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Dynamo Module Validation Test${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

FAILED_TESTS=0
PASSED_TESTS=0

# Test function
test_image() {
    local image="$1"
    local module="$2"
    local test_name="$3"

    echo -e "${YELLOW}Testing:${NC} $test_name"
    echo "  Image:  $image"
    echo "  Module: $module"
    echo ""

    # Test 1: Check if dynamo package exists
    echo "  [1/5] Checking if dynamo package is installed..."
    if docker run --rm --entrypoint bash "$image" -c "python -c 'import dynamo' 2>/dev/null"; then
        echo -e "        ${GREEN}✓ dynamo package found${NC}"
    else
        echo -e "        ${RED}✗ dynamo package NOT found${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Test 2: Check if specific module exists
    echo "  [2/5] Checking if $module module is installed..."
    if docker run --rm --entrypoint bash "$image" -c "python -c 'import $module' 2>/dev/null"; then
        echo -e "        ${GREEN}✓ $module module found${NC}"
    else
        echo -e "        ${RED}✗ $module module NOT found${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Test 3: Check module location
    echo "  [3/5] Checking module location..."
    MODULE_PATH=$(docker run --rm --entrypoint bash "$image" -c "python -c 'import $module; print($module.__file__)' 2>/dev/null" || echo "FAILED")
    if [ "$MODULE_PATH" != "FAILED" ] && [ -n "$MODULE_PATH" ]; then
        echo -e "        ${GREEN}✓ Module location: $MODULE_PATH${NC}"
    else
        echo -e "        ${RED}✗ Failed to get module location${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Test 4: Check VIRTUAL_ENV is set
    echo "  [4/5] Checking VIRTUAL_ENV environment variable..."
    VENV=$(docker run --rm --entrypoint bash "$image" -c "echo \$VIRTUAL_ENV")
    if [ -n "$VENV" ]; then
        echo -e "        ${GREEN}✓ VIRTUAL_ENV=$VENV${NC}"
    else
        echo -e "        ${RED}✗ VIRTUAL_ENV not set${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Test 5: Check venv bin is in PATH
    echo "  [5/5] Checking if venv/bin is in PATH..."
    PATH_CHECK=$(docker run --rm --entrypoint bash "$image" -c "echo \$PATH | grep -o '\$VIRTUAL_ENV/bin' || echo 'NOT_FOUND'")
    if [ "$PATH_CHECK" != "NOT_FOUND" ]; then
        echo -e "        ${GREEN}✓ \$VIRTUAL_ENV/bin is in PATH${NC}"
    else
        echo -e "        ${YELLOW}⚠ \$VIRTUAL_ENV/bin not explicitly in PATH (might use absolute path)${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ All tests passed for $test_name${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo ""
    return 0
}

# Test dynamo-vllm:slim
if docker images | grep -q "dynamo-vllm.*slim"; then
    test_image "dynamo-vllm:slim" "dynamo.vllm" "dynamo-vllm:slim"
else
    echo -e "${YELLOW}⊘ Image dynamo-vllm:slim not found (skipping)${NC}"
    echo ""
fi

# Test dynamo-trtllm:slim
if docker images | grep -q "dynamo-trtllm.*slim"; then
    test_image "dynamo-trtllm:slim" "dynamo.trtllm" "dynamo-trtllm:slim"
else
    echo -e "${YELLOW}⊘ Image dynamo-trtllm:slim not found (skipping)${NC}"
    echo ""
fi

# Test dynamo-vllm-efa:slim-a10g (if exists)
if docker images | grep -q "dynamo-vllm-efa.*slim-a10g"; then
    test_image "dynamo-vllm-efa:slim-a10g" "dynamo.vllm" "dynamo-vllm-efa:slim-a10g"
else
    echo -e "${YELLOW}⊘ Image dynamo-vllm-efa:slim-a10g not found (skipping)${NC}"
    echo ""
fi

# Test dynamo-trtllm-efa:slim-a10g (if exists)
if docker images | grep -q "dynamo-trtllm-efa.*slim-a10g"; then
    test_image "dynamo-trtllm-efa:slim-a10g" "dynamo.trtllm" "dynamo-trtllm-efa:slim-a10g"
else
    echo -e "${YELLOW}⊘ Image dynamo-trtllm-efa:slim-a10g not found (skipping)${NC}"
    echo ""
fi

# Summary
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Tests passed: ${GREEN}$PASSED_TESTS${NC}"
echo "  Tests failed: ${RED}$FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}✗ VALIDATION FAILED${NC}"
    echo ""
    echo "The dynamo module is not properly installed in one or more images."
    echo ""
    echo "Common causes:"
    echo "  1. VIRTUAL_ENV used in ENV before it's defined in Dockerfile"
    echo "  2. Dynamo wheelhouse not properly copied/installed"
    echo "  3. Virtual environment path mismatch between build stages"
    echo ""
    echo "To fix, ensure:"
    echo "  1. VIRTUAL_ENV is defined BEFORE using it in PATH"
    echo "  2. Dynamo wheels are installed with: uv pip install /opt/dynamo/wheelhouse/ai_dynamo*.whl"
    echo "  3. Virtual environment path is consistent across all stages"
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo ""
    echo "All container images have the dynamo module properly installed."
    echo ""
    exit 0
fi
