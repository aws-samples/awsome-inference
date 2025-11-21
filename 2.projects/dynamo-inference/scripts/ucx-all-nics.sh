#!/bin/bash
# UCX test to utilize ALL 32 EFA devices
# Based on your monitoring showing only 2/32 devices active

echo "UCX Test - Utilizing ALL 32 EFA Devices"
echo "========================================"
echo ""
echo "Current status: Only 2 devices active (rdmap79s0, rdmap113s0)"
echo "Goal: Activate all 32 devices for maximum bandwidth"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Explicitly list all devices"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Create a comma-separated list of all devices:"
echo 'export UCX_TLS=srd,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=rdmap79s0:1,rdmap80s0:1,rdmap81s0:1,rdmap82s0:1,rdmap96s0:1,rdmap97s0:1,rdmap98s0:1,rdmap99s0:1,rdmap113s0:1,rdmap114s0:1,rdmap115s0:1,rdmap116s0:1,rdmap130s0:1,rdmap131s0:1,rdmap132s0:1,rdmap133s0:1,rdmap147s0:1,rdmap148s0:1,rdmap149s0:1,rdmap150s0:1,rdmap164s0:1,rdmap165s0:1,rdmap166s0:1,rdmap167s0:1,rdmap181s0:1,rdmap182s0:1,rdmap183s0:1,rdmap184s0:1,rdmap198s0:1,rdmap199s0:1,rdmap200s0:1,rdmap201s0:1'
echo 'CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 1073741824 -n 10 -p 10015'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Use mlx pattern (if these are Mellanox devices)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo 'export UCX_TLS=srd,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=mlx*'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 1073741824 -n 10 -p 10016'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Multi-rail with all devices"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo 'export UCX_TLS=srd,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_MAX_RNDV_RAILS=32'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 1073741824 -n 10 -p 10017'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Force multi-rail with SRD-specific settings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo 'export UCX_TLS=srd,cuda_copy,cuda_ipc'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_MAX_RNDV_RAILS=32'
echo 'export UCX_MAX_EAGER_RAILS=32'
echo 'export UCX_IB_NUM_PATHS=32'
echo 'export UCX_SRD_SEG_SIZE=8192'
echo 'CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 1073741824 -n 10 -p 10018'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Large buffer with rail striping"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo 'export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_MAX_RNDV_RAILS=32'
echo 'export UCX_MAX_EAGER_RAILS=32'
echo 'export UCX_RNDV_SCHEME=put_rail'
echo 'export UCX_RNDV_THRESH=1024'
echo 'export UCX_SRD_SEG_SIZE=16384'
echo 'CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 8589934592 -n 20 -w 10 -p 10019'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Force device distribution"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo 'export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy'
echo 'export UCX_NET_DEVICES=all'
echo 'export UCX_MAX_RNDV_RAILS=32'
echo 'export UCX_UNIFIED_MODE=y'
echo 'export UCX_BCOPY_THRESH=0'
echo 'export UCX_RNDV_THRESH=1024'
echo 'export UCX_WARN_UNUSED_ENV_VARS=n'
echo 'CUDA_VISIBLE_DEVICES=0 ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s 8589934592 -n 20 -w 10 -p 10020'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Monitor which test activates more devices using your monitoring tool."
echo ""
echo "Expected results:"
echo "- Current: 2 devices @ ~359 MB/s each = ~718 MB/s total"
echo "- Target: 32 devices @ ~359 MB/s each = ~11.5 GB/s total"
echo ""
echo "Key settings to force multi-device usage:"
echo "- UCX_MAX_RNDV_RAILS=32 - Use 32 rails for rendezvous"
echo "- UCX_MAX_EAGER_RAILS=32 - Use 32 rails for eager messages"
echo "- UCX_RNDV_SCHEME=put_rail - Use rail-based PUT scheme"
echo "- UCX_RNDV_THRESH=1024 - Lower threshold to use rails sooner"
echo ""