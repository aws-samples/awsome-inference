#!/usr/bin/env python3
"""2-node 16-GPU AllReduce benchmark using torch.distributed. Launched per-rank."""
import os, time, json, sys
import torch
import torch.distributed as dist

def main():
    rank = int(os.environ["RANK"])
    local_rank = int(os.environ["LOCAL_RANK"])
    world_size = int(os.environ["WORLD_SIZE"])
    master_addr = os.environ["MASTER_ADDR"]
    master_port = os.environ.get("MASTER_PORT", "29500")

    torch.cuda.set_device(local_rank)
    dist.init_process_group(
        backend="nccl",
        init_method=f"tcp://{master_addr}:{master_port}",
        world_size=world_size,
        rank=rank,
        timeout=__import__("datetime").timedelta(seconds=300),
    )
    if rank == 0:
        print(f"[t11] init OK: world_size={world_size} nccl_ver={torch.cuda.nccl.version()}", flush=True)

    # Sweep sizes (bytes) from 1 MiB to 1 GiB, step x2
    results = []
    for size_mb in [1, 4, 16, 64, 256, 1024]:
        n = size_mb * 1024 * 1024 // 4  # float32
        x = torch.ones(n, dtype=torch.float32, device="cuda")
        # Warmup
        for _ in range(3):
            dist.all_reduce(x)
        torch.cuda.synchronize()
        t0 = time.time()
        iters = 10
        for _ in range(iters):
            dist.all_reduce(x)
        torch.cuda.synchronize()
        t1 = time.time()
        sec_per = (t1 - t0) / iters
        bytes_per = size_mb * 1024 * 1024
        algbw = bytes_per / sec_per / 1e9
        busbw = algbw * 2 * (world_size - 1) / world_size
        if rank == 0:
            print(f"[t11] size={size_mb:>5} MiB  time={sec_per*1000:>7.2f} ms  algbw={algbw:>6.2f} GB/s  busbw={busbw:>6.2f} GB/s", flush=True)
            results.append({"size_mb": size_mb, "ms": sec_per*1000, "algbw_gbps": algbw, "busbw_gbps": busbw})

    if rank == 0:
        with open("/tmp/t11-results.json", "w") as f:
            json.dump({"world_size": world_size, "results": results}, f, indent=2)
        print(f"[t11] wrote /tmp/t11-results.json", flush=True)
    dist.destroy_process_group()

if __name__ == "__main__":
    main()
