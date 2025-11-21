#!/bin/bash
# Fixed UCX configuration for AWS EFA - avoiding UD transport errors
# Using RC (Reliable Connection) transport which works properly with EFA

echo "UCX Test Commands for AWS EFA - Fixed Configuration"
echo "===================================================="
echo ""
echo "The UD (Unreliable Datagram) transport causes errors with EFA."
echo "We'll use RC (Reliable Connection) transport instead."
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Fixed baseline with RC transport only"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Run this command (avoiding UD transport):"
echo 'export UCX_TLS=rc,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=all'
echo 'ucx_perftest -t ucp_put_bw -m cuda -s 2147483648 -n 10 -w 5 -p 10006 10.1.238.41'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: RC transport with multi-path"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Add multi-path support:"
echo 'export UCX_TLS=rc,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'ucx_perftest -t ucp_put_bw -m cuda -s 2147483648 -n 10 -w 5 -p 10007 10.1.238.41'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: RC transport with multi-rail"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Add multi-rail support:"
echo 'export UCX_TLS=rc,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'export UCX_MAX_RNDV_RAILS=32'
echo 'ucx_perftest -t ucp_put_bw -m cuda -s 2147483648 -n 10 -w 5 -p 10008 10.1.238.41'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Alternative - Use TCP transport selection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Let UCX auto-select transports excluding UD:"
echo 'export UCX_TLS=tcp,cuda_copy,cuda_ipc,rc_verbs,rc_mlx5'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'ucx_perftest -t ucp_put_bw -m cuda -s 2147483648 -n 10 -w 5 -p 10009 10.1.238.41'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Explicitly exclude UD transport"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Explicitly exclude UD while keeping IB:"
echo 'export UCX_TLS=^ud,ib,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'ucx_perftest -t ucp_put_bw -m cuda -s 2147483648 -n 10 -w 5 -p 10010 10.1.238.41'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Maximum performance with RC transport"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Full optimization with RC transport:"
echo 'export UCX_TLS=rc,cuda_copy,cuda_ipc,gdr_copy'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'export UCX_MAX_RNDV_RAILS=32'
echo 'export UCX_RNDV_THRESH=8192'
echo 'export UCX_ZCOPY_THRESH=32768'
echo 'export UCX_RC_FC_ENABLE=n'
echo 'export UCX_IB_REG_METHODS=rcache,odp'
echo 'export UCX_IB_GID_INDEX=auto'
echo 'ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 20 -w 10 -p 10011 10.1.238.41'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: EFA-specific configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# EFA-optimized settings:"
echo 'export UCX_TLS=rc_verbs,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'export UCX_MAX_RNDV_RAILS=32'
echo 'export FI_EFA_USE_DEVICE_RDMA=1'
echo 'export FI_PROVIDER=efa'
echo 'export FI_EFA_FORK_SAFE=1'
echo 'ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 20 -w 10 -p 10012 10.1.238.41'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Notes:"
echo "1. The error 'failed to create UD QP' is common with EFA"
echo "2. EFA primarily uses RC (Reliable Connection) transport"
echo "3. UD (Unreliable Datagram) is not well supported on EFA"
echo "4. Using 'rc' or 'rc_verbs' or 'rc_mlx5' avoids the issue"
echo "5. The '^ud' prefix explicitly excludes UD transport"
echo ""
echo "Try Test 1 first to verify it works without errors,"
echo "then proceed with the optimizations."
echo ""