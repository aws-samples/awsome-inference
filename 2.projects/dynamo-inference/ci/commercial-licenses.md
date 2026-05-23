# Commercial-license callouts

This workshop builds and distributes Docker images containing components
with commercial / special licensing requirements that Amazon OSA's
distribution-review process requires to be flagged explicitly.

## Images affected

All images that derive from `nvcr.io/nvidia/cuda-dl-base` or
`nvcr.io/nvidia/ai-dynamo/*` base images (i.e. all shipping images produced
by this project: `awsi-efa-base`, `awsi-dynamo-combined-efa`) carry
NVIDIA's commercial software SLA in addition to the OSS licenses of the
individual components.

`FROM` chain (100% public, reproducible by any consumer with Docker + network):

| Upstream | License |
|---|---|
| `nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04` | NVIDIA CUDA EULA (commercial) |
| `nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.0.1`           | NVIDIA AI Enterprise EULA (commercial) |
| `nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.0.1`                  | NVIDIA AI Enterprise EULA (commercial) |
| `aquasec/trivy:latest` (scanner-only, NOT in final ancestry)   | Apache-2.0 |
| `anchore/syft:latest`  (scanner-only, NOT in final ancestry)   | Apache-2.0 |

## Components requiring Business Line Lawyer approval

| Component | Notes |
|---|---|
| NVIDIA CUDA Toolkit | Inlined build on cuda-dl-base (12.9+). Commercial SLA. |
| NVIDIA NCCL | Built from source (v2.30.3+). Commercial SLA. |
| NVIDIA NIXL | Built from source (1.0.1+). Commercial SLA. |
| NVIDIA GDRCopy | Built from source (2.5.2+). Commercial SLA. |
| NVIDIA cuBLAS / cuDNN / cuFFT | Shipped by cuda-dl-base. Commercial SLA. |
| NVIDIA Nsight Systems | Shipped by cuda-dl-base (we strip `nic_sampler` for CVE-2025-68121). Commercial SLA. |
| NVIDIA NeMo Evaluator | pip-installed in runtime stage. Commercial SLA. |
| TensorRT-LLM | dynamo-combined-efa with DYNAMO_BACKEND=trtllm. Commercial SLA (NVIDIA AI Enterprise EULA). |
| vLLM | dynamo-combined-efa with DYNAMO_BACKEND=vllm. Apache-2.0 but bundled with commercial NVIDIA stack. |
| aws-ofi-nccl | Apache-2.0 but links against NCCL. |

## What to do before distributing

1. Confirm access to the components in the target region / account through
   the NVIDIA NGC EULA.
2. File a distribution-review ticket (OSA) citing:
   - This `ci/commercial-licenses.md`
   - `THIRD-PARTY-LICENSES` at project root for the full OSS inventory
   - `UTILITY-LICENSES` at project root for build/dev tools
   - `sbom/` for machine-readable SBOMs (SPDX + CycloneDX)
   - `sbom/CVE-SUMMARY.md` for the trivy CVE ground-truth
   - `ATTRIBUTION.md` for NVIDIA/community attribution
3. Obtain Business-Line-Lawyer sign-off on the commercial components.

## Not on this list

Components that are pure OSS (Apache-2.0 / MIT / BSD) are tracked only in
`THIRD-PARTY-LICENSES`. Commercial or uncommon-license components should
also appear there, but they additionally require the explicit callout
here so reviewers don't have to reverse-engineer the inventory.
