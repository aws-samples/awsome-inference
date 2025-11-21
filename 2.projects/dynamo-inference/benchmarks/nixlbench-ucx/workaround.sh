#!/bin/bash
#
# NIXL UCX Backend Workarounds
#
# This script contains workarounds for common UCX backend issues,
# particularly the "target uri is not valid" ETCD error.
#
# Usage:
#   source ./workaround.sh              # Apply all workarounds
#   source ./workaround.sh dram         # DRAM-only workaround
#   source ./workaround.sh etcd         # ETCD-only workaround
#   source ./workaround.sh minimal      # Minimal UCX config

WORKAROUND_TYPE="${1:-all}"

echo "==================================================================="
echo "NIXL UCX Backend Workarounds"
echo "==================================================================="
echo ""

# Detect if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script must be sourced, not executed"
    echo "Usage: source ./workaround.sh [all|dram|etcd|minimal]"
    exit 1
fi

echo "Applying workaround type: $WORKAROUND_TYPE"
echo ""

#=============================================================================
# WORKAROUND 1: Use DRAM Instead of VRAM
#=============================================================================
# Issue: UCX has issues with GPU memory (VRAM) management
# Solution: Force use of CPU memory (DRAM) for buffers
# Impact: Reduces performance but improves stability

apply_dram_workaround() {
    echo "Workaround 1: DRAM Instead of VRAM"
    echo "-----------------------------------"
    echo "Issue: UCX struggles with GPU memory management"
    echo "Solution: Use CPU memory for communication buffers"
    echo "Impact: Lower performance but better stability"
    echo ""

    export NIXL_USE_DRAM=1
    export NIXL_BUFFER_TYPE=cpu
    export NIXL_FORCE_CPU_BUFFERS=1

    # Disable CUDA memory pool which can cause issues
    export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False

    echo "✓ DRAM workaround applied"
    echo "  NIXL_USE_DRAM=1"
    echo "  NIXL_BUFFER_TYPE=cpu"
    echo "  NIXL_FORCE_CPU_BUFFERS=1"
    echo ""
}

#=============================================================================
# WORKAROUND 2: Alternative ETCD Configuration
#=============================================================================
# Issue: "target uri is not valid" ETCD error
# Solution: Use alternative connection parameters and timeouts
# Impact: May improve connection reliability

apply_etcd_workaround() {
    echo "Workaround 2: Alternative ETCD Configuration"
    echo "---------------------------------------------"
    echo "Issue: 'target uri is not valid' ETCD error"
    echo "Solution: Adjusted timeouts and connection parameters"
    echo "Impact: May improve ETCD connection reliability"
    echo ""

    export NIXL_STORE_TYPE=etcd
    export NIXL_ETCD_ENDPOINTS="http://127.0.0.1:29501"

    # Increase timeouts
    export NIXL_ETCD_TIMEOUT=30
    export NIXL_ETCD_CONNECT_TIMEOUT=10
    export NIXL_ETCD_REQUEST_TIMEOUT=5

    # Connection parameters
    export NIXL_ETCD_KEEP_ALIVE_TIME=10
    export NIXL_ETCD_KEEP_ALIVE_TIMEOUT=3

    # Retry settings
    export NIXL_ETCD_MAX_RETRIES=5
    export NIXL_ETCD_RETRY_DELAY=2

    echo "✓ ETCD workaround applied"
    echo "  NIXL_ETCD_TIMEOUT=30"
    echo "  NIXL_ETCD_CONNECT_TIMEOUT=10"
    echo "  NIXL_ETCD_MAX_RETRIES=5"
    echo ""
}

#=============================================================================
# WORKAROUND 3: Minimal UCX Configuration
#=============================================================================
# Issue: Complex UCX transport layers cause issues
# Solution: Use minimal TCP-only configuration
# Impact: Lower performance but better compatibility

apply_minimal_ucx_workaround() {
    echo "Workaround 3: Minimal UCX Configuration"
    echo "----------------------------------------"
    echo "Issue: Complex UCX transports cause failures"
    echo "Solution: Use minimal TCP-only setup"
    echo "Impact: Lowest performance but best stability"
    echo ""

    # Minimal transport: TCP only
    export UCX_TLS=tcp
    export UCX_NET_DEVICES=lo

    # Disable advanced features
    export UCX_MEMTYPE_CACHE=n
    export UCX_IB_ENABLE=n
    export UCX_CUDA_IPC_CACHE=n

    # Conservative settings
    export UCX_TCP_TX_SEG_SIZE=8192
    export UCX_TCP_RX_SEG_SIZE=8192

    # Disable RDMA features
    export UCX_RNDV_SCHEME=put_zcopy
    export UCX_RNDV_THRESH=8192

    echo "✓ Minimal UCX workaround applied"
    echo "  UCX_TLS=tcp (no CUDA features)"
    echo "  UCX_MEMTYPE_CACHE=n"
    echo "  UCX_IB_ENABLE=n"
    echo ""
}

#=============================================================================
# WORKAROUND 4: Standard UCX Configuration (Less Restrictive)
#=============================================================================
# Issue: Need CUDA features but default config fails
# Solution: Balanced configuration with CUDA but conservative settings
# Impact: Moderate performance, moderate stability

apply_standard_ucx_workaround() {
    echo "Workaround 4: Standard UCX Configuration"
    echo "-----------------------------------------"
    echo "Issue: Need CUDA features but full config fails"
    echo "Solution: Balanced CUDA + TCP configuration"
    echo "Impact: Moderate performance and stability"
    echo ""

    # Standard transport with CUDA
    export UCX_TLS=tcp,cuda_copy,cuda_ipc
    export UCX_NET_DEVICES=lo

    # Disable problematic features
    export UCX_MEMTYPE_CACHE=n
    export UCX_IB_ENABLE=n

    # CUDA IPC settings
    export UCX_CUDA_IPC_CACHE=n
    export UCX_CUDA_COPY_MAX_REG_RATIO=0.5

    # Conservative buffer sizes
    export UCX_TCP_TX_SEG_SIZE=16384
    export UCX_TCP_RX_SEG_SIZE=16384

    echo "✓ Standard UCX workaround applied"
    echo "  UCX_TLS=tcp,cuda_copy,cuda_ipc"
    echo "  UCX_MEMTYPE_CACHE=n"
    echo "  UCX_CUDA_IPC_CACHE=n"
    echo ""
}

#=============================================================================
# WORKAROUND 5: Disable UCX Warning/Error Suppression
#=============================================================================
# Issue: Hidden errors make debugging difficult
# Solution: Enable verbose UCX logging
# Impact: Better debugging information

apply_verbose_logging_workaround() {
    echo "Workaround 5: Verbose Logging"
    echo "------------------------------"
    echo "Enable detailed UCX and NIXL logging for debugging"
    echo ""

    # UCX logging
    export UCX_LOG_LEVEL=info
    export UCX_LOG_PRINT_ENABLE=y

    # NIXL logging
    export NIXL_LOG_LEVEL=DEBUG
    export NIXL_VERBOSE=1

    # PyTorch distributed logging
    export TORCH_DISTRIBUTED_DEBUG=DETAIL
    export TORCH_SHOW_CPP_STACKTRACES=1

    echo "✓ Verbose logging enabled"
    echo "  UCX_LOG_LEVEL=info"
    echo "  NIXL_LOG_LEVEL=DEBUG"
    echo "  TORCH_DISTRIBUTED_DEBUG=DETAIL"
    echo ""
}

#=============================================================================
# WORKAROUND 6: Alternative Store Backend
#=============================================================================
# Issue: ETCD is problematic
# Solution: Try file-based or TCP store instead
# Impact: Avoids ETCD entirely

apply_alternative_store_workaround() {
    echo "Workaround 6: Alternative Store Backend"
    echo "----------------------------------------"
    echo "Issue: ETCD 'target uri is not valid' error"
    echo "Solution: Use TCP store instead of ETCD"
    echo "Impact: Avoids ETCD completely"
    echo ""

    # Use TCP store instead of ETCD
    unset NIXL_STORE_TYPE
    unset NIXL_ETCD_ENDPOINTS
    unset NIXL_ETCD_TIMEOUT
    unset NIXL_ETCD_CONNECT_TIMEOUT

    export NIXL_STORE_TYPE=tcp
    export NIXL_TCP_STORE_ADDR=127.0.0.1
    export NIXL_TCP_STORE_PORT=29500

    echo "✓ Alternative store workaround applied"
    echo "  NIXL_STORE_TYPE=tcp (avoiding ETCD)"
    echo "  NIXL_TCP_STORE_ADDR=127.0.0.1"
    echo "  NIXL_TCP_STORE_PORT=29500"
    echo ""
}

#=============================================================================
# Apply Workarounds Based on Type
#=============================================================================

case "$WORKAROUND_TYPE" in
    dram)
        echo "Applying DRAM-only workaround..."
        echo ""
        apply_dram_workaround
        ;;

    etcd)
        echo "Applying ETCD-only workaround..."
        echo ""
        apply_etcd_workaround
        ;;

    minimal)
        echo "Applying minimal UCX configuration..."
        echo ""
        apply_minimal_ucx_workaround
        apply_etcd_workaround
        ;;

    standard)
        echo "Applying standard workarounds..."
        echo ""
        apply_standard_ucx_workaround
        apply_etcd_workaround
        ;;

    no-etcd)
        echo "Applying no-ETCD workaround..."
        echo ""
        apply_alternative_store_workaround
        apply_standard_ucx_workaround
        ;;

    verbose)
        echo "Applying verbose logging..."
        echo ""
        apply_verbose_logging_workaround
        ;;

    all|*)
        echo "Applying all workarounds..."
        echo ""
        apply_dram_workaround
        apply_etcd_workaround
        apply_standard_ucx_workaround
        apply_verbose_logging_workaround
        ;;
esac

#=============================================================================
# Summary and Recommendations
#=============================================================================

echo "==================================================================="
echo "Workarounds Applied Successfully"
echo "==================================================================="
echo ""
echo "Current Configuration:"
env | grep -E "^(UCX_|NIXL_|TORCH_)" | sort
echo ""
echo "==================================================================="
echo "Important Notes:"
echo "==================================================================="
echo ""
echo "1. Even with workarounds, UCX performance is poor (~0.85 GB/s)"
echo "2. LIBFABRIC achieves 21x better performance (~18 GB/s)"
echo "3. These workarounds improve stability, not performance"
echo "4. Some workarounds may fail depending on system configuration"
echo ""
echo "Recommended Testing Order:"
echo "  1. source ./workaround.sh no-etcd    # Avoid ETCD entirely"
echo "  2. source ./workaround.sh minimal    # Minimal UCX config"
echo "  3. source ./workaround.sh dram       # Use DRAM instead of VRAM"
echo "  4. source ./workaround.sh standard   # Standard with workarounds"
echo "  5. source ./workaround.sh all        # Everything enabled"
echo ""
echo "If all workarounds fail:"
echo "  → Use LIBFABRIC backend instead (highly recommended)"
echo ""
echo "==================================================================="
echo ""

#=============================================================================
# Helper Functions
#=============================================================================

# Function to test ETCD connectivity
test_etcd_connection() {
    local etcd_endpoint="${NIXL_ETCD_ENDPOINTS:-http://127.0.0.1:29501}"
    local health_url="${etcd_endpoint}/health"

    echo "Testing ETCD connection to: $health_url"

    if curl -s --max-time 5 "$health_url" > /dev/null 2>&1; then
        echo "✓ ETCD is accessible"
        return 0
    else
        echo "✗ ETCD is not accessible"
        echo "  Make sure ETCD server is running"
        return 1
    fi
}

# Function to verify UCX is available
test_ucx_available() {
    echo "Testing UCX availability..."

    if python3 -c "import torch; import torch.distributed as dist" 2>/dev/null; then
        echo "✓ PyTorch distributed is available"
    else
        echo "✗ PyTorch distributed not available"
        return 1
    fi

    # Try to get UCX version
    if ucx_info -v 2>/dev/null | head -5; then
        echo "✓ UCX library found"
    else
        echo "⚠ UCX library may not be installed"
        echo "  (This may be OK if UCX is bundled with PyTorch)"
    fi

    return 0
}

# Function to show current workaround status
show_workaround_status() {
    echo ""
    echo "==================================================================="
    echo "Current Workaround Status"
    echo "==================================================================="
    echo ""

    echo "UCX Configuration:"
    env | grep "^UCX_" | sed 's/^/  /' || echo "  (none set)"
    echo ""

    echo "NIXL Configuration:"
    env | grep "^NIXL_" | sed 's/^/  /' || echo "  (none set)"
    echo ""

    echo "PyTorch Configuration:"
    env | grep "^TORCH_" | sed 's/^/  /' || echo "  (none set)"
    echo ""

    echo "==================================================================="
    echo ""
}

# Export helper functions
export -f test_etcd_connection
export -f test_ucx_available
export -f show_workaround_status

echo "Helper functions available:"
echo "  test_etcd_connection  - Check if ETCD is accessible"
echo "  test_ucx_available    - Verify UCX library is present"
echo "  show_workaround_status - Display current configuration"
echo ""
echo "Example: test_etcd_connection"
echo ""
