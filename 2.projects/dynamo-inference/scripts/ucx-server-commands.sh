#!/bin/bash
# UCX Server Commands - Run these on the FIRST node (server)
# This node should start FIRST before the client

echo "═══════════════════════════════════════════════════════════"
echo "     UCX SERVER COMMANDS - RUN ON FIRST NODE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Your server IP: 10.1.238.41"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Option 1: Basic SRD test (already working)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Run this on server (FIRST):"
cat << 'EOF'
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=rdmap113s0:1
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 100000000 -n 10 -p 10006
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Option 2: Multi-rail test with all 32 NICs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Run this on server (FIRST):"
cat << 'EOF'
export UCX_TLS=srd,cuda_copy,cuda_ipc
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_IB_NUM_PATHS=32
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 1073741824 -n 10 -p 10017
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Option 3: Large buffer with rail striping (best for 32 NICs)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Run this on server (FIRST):"
cat << 'EOF'
export UCX_TLS=srd,cuda_copy,cuda_ipc,gdr_copy
export UCX_NET_DEVICES=all
export UCX_MAX_RNDV_RAILS=32
export UCX_MAX_EAGER_RAILS=32
export UCX_RNDV_SCHEME=put_rail
export UCX_RNDV_THRESH=1024
export UCX_SRD_SEG_SIZE=16384
export UCX_WARN_UNUSED_ENV_VARS=n
CUDA_VISIBLE_DEVICES=0 ucx_perftest -t ucp_put_bw -m cuda -s 8589934592 -n 20 -w 10 -p 10019
EOF
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "IMPORTANT NOTES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. This node acts as the SERVER - start it FIRST"
echo "2. The server will wait for client connection"
echo "3. You'll see output like:"
echo "   'Waiting for connection...'"
echo ""
echo "4. After starting the server, go to the SECOND node and run"
echo "   the corresponding client command with the same port"
echo ""
echo "5. The client command will be the same but with IP at the end:"
echo "   ucx_perftest 10.1.238.41 -t ucp_put_bw -m cuda -s ... -p ..."
echo ""
echo "6. Monitor your network dashboard to see which NICs become active"
echo ""
echo "Start with Option 2 or 3 to test multi-NIC performance!"
echo ""