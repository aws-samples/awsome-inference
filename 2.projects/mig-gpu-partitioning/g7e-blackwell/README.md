<h3 align="center">MIG on Amazon EC2 G7e (NVIDIA RTX PRO 6000 Blackwell Server Edition) with EKS</h3>

---

This directory is a companion to the parent [`mig-gpu-partitioning`](../) guide, which walks through MIG on a `p5.48xlarge` (H100). Here we do the same on the smallest G7e size — `g7e.2xlarge` — which ships a single **NVIDIA RTX PRO 6000 Blackwell Server Edition** GPU.

Blackwell RTX PRO 6000 supports MIG with a different granularity than A100/H100: up to **4 GPU instances per physical GPU** (vs. 7 on A100/H100), with memory/compute slice sizes determined by the SKU and current driver. Because a `g7e.2xlarge` is a single-GPU node, this setup is the cheapest way to exercise MIG end-to-end on EKS.

## Scripts

| Script | What it does |
|---|---|
| `env.sh` | Shared environment (region, cluster, instance type, labels, taints). Source this; don't run it. |
| `01-create-nodegroup.sh` | Creates an EKS managed nodegroup `g7e-mig-test` with one `g7e.2xlarge`, reusing the IAM role of an existing `*gpu*` nodegroup. |
| `02-install-gpu-operator.sh` | `helm install` NVIDIA GPU Operator with `mig.strategy=mixed` and `migManager.enabled=true` (default `all-disabled` — we flip MIG on in step 3). |
| `03-apply-mig-config.sh` | Labels the node `nvidia.com/mig.config=<profile>` so mig-manager partitions the GPU. Default profile: `all-1g.24gb` (4 equal 24 GiB partitions). |
| `04-test-mig.sh` | Schedules a short-lived pod that requests one `nvidia.com/mig-*` slice, runs `nvidia-smi`, and dumps the node's advertised MIG resources. |
| `99-cleanup.sh` | Uninstalls the operator and deletes the nodegroup — this is what stops g7e on-demand billing. |

## Prerequisites

These scripts assume an EKS cluster is already up. If you don't have one, start from the [`1.infrastructure/`](../../../1.infrastructure) guide to provision a VPC + EKS cluster. You'll then need:

- `aws` CLI with credentials for the target account (defaults to `us-west-2`; override via `AWS_REGION` / `CLUSTER_NAME`)
- `kubectl`, `helm`, `jq`, and `python3` on `PATH`
- An existing EKS cluster with at least one GPU managed nodegroup whose IAM role we can reuse (the scripts auto-detect one named `*gpu*`). For a permanent setup you should provision a dedicated node role instead — see the note at the bottom.
- G-instance vCPU quota in the target region (g7e is covered by the "Running On-Demand G and VT instances" quota)
- Private subnets in an AZ where g7e actually has capacity (see the [Capacity](#capacity-insufficientinstancecapacity) section below — in us-west-2 we only found g7e.2xlarge capacity in 2d during testing)

> **Heads up on `AWS_REGION`**: the scripts default to `us-west-2` via `${AWS_REGION:-us-west-2}`, so if your shell already exports `AWS_REGION=<something-else>` that wins and the scripts will try to talk to a cluster in the wrong region. Either `unset AWS_REGION` before running, or prefix each command with `AWS_REGION=us-west-2`.

## Usage

```bash
# 0. (Optional) override any defaults in env.sh
export AWS_REGION=us-west-2
export CLUSTER_NAME=osmo

# If a specific AZ has g7e capacity, pin it:
# export SUBNETS=subnet-0abc,subnet-0def

# 1. Spin up the node (starts on-demand billing)
./01-create-nodegroup.sh

# 2. Install the NVIDIA GPU Operator with MIG manager
./02-install-gpu-operator.sh

# 3. Partition the GPU
./03-apply-mig-config.sh
# or pick a different profile:
MIG_PROFILE=all-balanced ./03-apply-mig-config.sh

# 4. Run a smoke-test pod on a MIG slice
./04-test-mig.sh

# 5. Tear everything down
./99-cleanup.sh
```

## Discovering valid MIG profiles

The set of profiles accepted by `nvidia.com/mig.config` comes from the `default-mig-parted-config` ConfigMap that the operator installs. To enumerate what's compiled in for Blackwell on your driver:

```bash
kubectl get configmap -n gpu-operator default-mig-parted-config \
  -o jsonpath='{.data.config\.yaml}' | yq '.mig-configs | keys'
```

To see the raw per-GPU profile list from the driver itself:

```bash
DRIVER_POD=$(kubectl get pod -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n gpu-operator "$DRIVER_POD" -- nvidia-smi mig -lgip
```

For the `g7e.2xlarge` (RTX PRO 6000 Server Edition, 96 GiB) SKU we verified the following profiles work:

| Profile | Partitions | Per-slice memory |
|---|---|---|
| `all-1g.24gb` (default) | 4 | ~24 GiB |
| `all-2g.48gb` | 2 | ~48 GiB |
| `all-4g.96gb` | 1 | ~95 GiB (whole GPU, MIG mode on) |

If your Blackwell SKU differs (different memory capacity or newer driver) pick a profile from the ConfigMap that matches what `nvidia-smi mig -lgip` reports.

## Capacity: `InsufficientInstanceCapacity`

G7e is supply-constrained. `aws ec2 describe-instance-type-offerings` will happily list g7e.2xlarge in every AZ of a region even when AWS has zero actual capacity in those AZs — **offering availability ≠ real capacity**. A dry-run `RunInstances` doesn't check capacity either (it only validates syntax/IAM).

When `01-create-nodegroup.sh` hits ICE, the nodegroup goes `CREATE_FAILED` with a health issue like:

```
AsgInstanceLaunchFailures: Could not launch On-Demand Instances.
InsufficientInstanceCapacity - We currently do not have sufficient g7e.2xlarge
capacity in the Availability Zone you requested (us-west-2a). ...
You can currently get g7e.2xlarge capacity by ... choosing us-west-2b, us-west-2c, us-west-2d.
```

A `CREATE_FAILED` nodegroup can't recover — the ASG keeps retrying past EKS's internal create timeout, so you can even end up with an instance that launched **after** EKS already gave up. Always run `./99-cleanup.sh` (or `aws eks delete-nodegroup …`) immediately when you see `CREATE_FAILED` so you don't get billed for an orphan instance.

Practical playbook:

1. Run `./01-create-nodegroup.sh` with all private subnets (default) and let ICE tell you which AZ currently has capacity.
2. Delete the failed nodegroup.
3. Re-run pinned to just that AZ: `SUBNETS=subnet-xxxxxxxx ./01-create-nodegroup.sh`.
4. If none of your VPC's private subnets are in an AZ with capacity, create one: an extra private subnet with `kubernetes.io/cluster/<cluster>=shared` tagged associated with an existing NAT route table. See `99-cleanup.sh` for the reverse (deleting the scratch subnet after teardown).

## Gotcha: AL2023 NVIDIA AMI + containerd v3 + gpu-operator v26

The EKS-optimized `AL2023_x86_64_NVIDIA` AMI ships **containerd v3**, which changes the plugin path layout (`io.containerd.cri.v1.runtime` instead of the v1/v2 `io.containerd.grpc.v1.cri`). The AMI's default `/etc/containerd/config.toml` does NOT include an explicit `SystemdCgroup = true` under the runc runtime — it relies on containerd's defaults.

The NVIDIA GPU operator (as of v26.3) ships a toolkit container (`container-toolkit:v1.19.0`) whose `nvidia-ctk runtime configure` command still emits a **v2-style drop-in** without `SystemdCgroup`. When that drop-in merges with the v3 base config, runc receives a non-systemd-shaped cgroupsPath and every single pod on the node starts failing with:

```
runc create failed: expected cgroupsPath to be of format "slice:prefix:name"
for systemd cgroups, got "/kubepods/besteffort/..." instead
```

This blocks the device plugin from ever advertising `nvidia.com/mig-*` and also takes `aws-node` down (breaking pod networking on the node).

`02-install-gpu-operator.sh` papers over this automatically by writing a correct v3 drop-in to `/etc/containerd/conf.d/99-nvidia.toml` containing both runc and nvidia runtimes with `SystemdCgroup = true`, then restarting `containerd` and `kubelet`. Without this patch, steps 3 and 4 will stall forever. If you're running these scripts on a different Blackwell AMI (say, a future AL2023 image where AWS pre-wires the nvidia runtime) you can drop the patch — check `containerd config dump | grep SystemdCgroup` and `crictl info` for the runtime section first.

## Notes & gotchas

- **Blackwell reboot**: mig-manager is configured with `WITH_REBOOT=true`. The very first MIG enable on a Blackwell node often requires a reboot before the partitions become visible; the node will cycle and the script will keep polling `nvidia.com/mig.config.state`. (In our testing on the `g7e.2xlarge` / driver 580.126 combo, the first enable succeeded without a reboot.)
- **Taints**: the nodegroup is tainted `nvidia.com/gpu=true:NoSchedule`. Pods must tolerate this to land on the node (step 4's smoke-test does).
- **Billing**: `g7e.2xlarge` is on-demand. The only way to stop billing is to delete the nodegroup — run `./99-cleanup.sh`. Verify no `g7e.*` instances remain at the end (the script prints a table).
- **EKS access for `kubectl`**: if `kubectl get nodes` fails with `the server has asked for the client to provide credentials`, your IAM principal doesn't have a cluster access entry yet. On a cluster with `authenticationMode=API` or `API_AND_CONFIG_MAP`, run:
  ```bash
  aws eks create-access-entry --cluster-name "$CLUSTER_NAME" \
    --principal-arn arn:aws:iam::<account>:user/<you> --type STANDARD
  aws eks associate-access-policy --cluster-name "$CLUSTER_NAME" \
    --principal-arn arn:aws:iam::<account>:user/<you> \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster
  ```
- **Why reuse an IAM role?**: the operator needs `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, and `AmazonEKS_CNI_Policy` on the node role. Reusing the role attached to an existing GPU nodegroup avoids provisioning a one-off role for a throwaway test. For a permanent setup, define your own.
