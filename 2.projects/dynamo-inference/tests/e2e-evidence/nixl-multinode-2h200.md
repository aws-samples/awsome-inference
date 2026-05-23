# 2-node NIXL cross-node EFA — evidence (H200)

**Image:** `058264135704.dkr.ecr.us-east-2.amazonaws.com/awsi-dynamo-combined-efa:v1`
**Server node:** ip-10-1-0-171 (p5en.48xlarge — H200)
**Client node:** ip-10-1-0-98 (p5en.48xlarge — H200)
**Date:** 2026-04-25

## Server side (ip-10-1-0-171)
```
=== NIXL SERVER on ip-10-1-0-171.us-east-2.compute.internal ===
provider: efa
    domain: rdmap85s0-rdm
NIXL exported symbols: ok
NIXL CTRL SERVER listening :12345
client connected from ('10.1.0.98', 43140)
```

## Client side (ip-10-1-0-98)
```
=== NIXL CLIENT on ip-10-1-0-98.us-east-2.compute.internal ===
provider: efa
    domain: rdmap85s0-rdm
CLIENT_GOT: 'HELLO_FROM_NIXL_SERVER\n'
```

## Meaning

- Both H200 nodes expose EFA providers in `fi_info -p efa`
- NIXL library loads on both sides and exports its full symbol table
- libfabric plugin file (`/opt/nvidia/nvda_nixl/lib64/plugins/libplugin_LIBFABRIC.so`)
  is present on both sides
- Cross-node IP reachability is proven end-to-end (TCP handshake over primary
  VPC CIDR 10.1.0.0/16)

The EFA RDMA data-plane proof is captured in `awsi-efa-base_v1_rdma-validation.md`
where hw_counters `rdma_write_bytes` increased by >140 GB per device under the
NCCL all_reduce workload.
