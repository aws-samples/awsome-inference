#!/bin/bash
# Runtime EFA detection — source this in container entrypoints
if [ -d "/sys/bus/pci/drivers/efa" ] && \
   { [ -f "/opt/amazon/ofi-nccl/lib/libnccl-net-ofi.so" ] || \
     [ -f "/opt/amazon/aws-ofi-nccl/lib/libnccl-net-ofi.so" ]; }; then
    export NCCL_NET_PLUGIN=ofi
    export NCCL_TUNER_PLUGIN=ofi
    echo "[detect-efa] EFA detected, NCCL_NET_PLUGIN=ofi NCCL_TUNER_PLUGIN=ofi"
fi
