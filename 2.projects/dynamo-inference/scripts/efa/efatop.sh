#!/bin/bash
# Lightweight efatop — reads EFA hw_counters in a loop
# For full efatop container, see: https://bit.ly/aws-do-efatop
INTERVAL=${1:-2}
while true; do
    clear
    echo "=== EFA Traffic Monitor ($(date)) ==="
    for dev in /sys/class/infiniband/rdmap*/ports/1/hw_counters; do
        NIC=$(echo "$dev" | grep -o 'rdmap[0-9]*s[0-9]*')
        TX=$(cat "$dev/tx_bytes" 2>/dev/null || echo 0)
        RX=$(cat "$dev/rx_bytes" 2>/dev/null || echo 0)
        TX_P=$(cat "$dev/tx_pkts" 2>/dev/null || echo 0)
        RX_P=$(cat "$dev/rx_pkts" 2>/dev/null || echo 0)
        printf "%-16s TX: %12s bytes (%8s pkts)  RX: %12s bytes (%8s pkts)\n" \
            "$NIC" "$TX" "$TX_P" "$RX" "$RX_P"
    done
    sleep "$INTERVAL"
done
