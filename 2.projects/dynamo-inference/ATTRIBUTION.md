# Attribution

This project incorporates components from various open-source projects. We acknowledge and are grateful to the developers and maintainers of these projects.

---

## NVIDIA Components

### NVIDIA Dynamo
- **Source:** https://github.com/ai-dynamo/dynamo
- **License:** Apache License 2.0
- **Description:** Open-source inference runtime for serving large language models at scale with disaggregated architecture.

### NVIDIA NCCL (NVIDIA Collective Communications Library)
- **Source:** https://github.com/NVIDIA/nccl
- **License:** BSD-3-Clause License
- **Description:** Optimized primitives for inter-GPU communication.

### NVIDIA NIXL (NVIDIA Inference Xfer Library)
- **Source:** https://github.com/NVIDIA/nixl
- **License:** Apache License 2.0
- **Description:** GPU-direct transfer library for efficient KV-cache movement in distributed inference.

### TensorRT-LLM
- **Source:** https://github.com/NVIDIA/TensorRT-LLM
- **License:** Apache License 2.0
- **Description:** High-performance inference library for large language models.

### CUDA Toolkit
- **Source:** https://developer.nvidia.com/cuda-toolkit
- **License:** NVIDIA CUDA Toolkit EULA
- **Description:** GPU computing platform and programming model.

---

## Communication Libraries

### UCX (Unified Communication X)
- **Source:** https://github.com/openucx/ucx
- **License:** BSD-3-Clause License
- **Description:** High-performance communication framework for CPU and GPU memory transfers.

### Libfabric
- **Source:** https://github.com/ofiwg/libfabric
- **License:** BSD-2-Clause License
- **Description:** Core component of the Open Fabrics Interfaces (OFI) framework.

### OpenMPI
- **Source:** https://github.com/open-mpi/ompi
- **License:** BSD-3-Clause License
- **Description:** Open-source Message Passing Interface implementation.

---

## AWS Components

### AWS EFA Installer
- **Source:** https://github.com/aws/aws-efa-installer
- **License:** Apache License 2.0
- **Description:** Installer for Elastic Fabric Adapter drivers and libraries.

### AWS OFI NCCL Plugin
- **Source:** https://github.com/aws/aws-ofi-nccl
- **License:** Apache License 2.0
- **Description:** Plugin to enable NCCL communication over AWS EFA.

---

## Container Base Images

### NVIDIA CUDA Container Images
- **Source:** https://hub.docker.com/r/nvidia/cuda
- **License:** NVIDIA Deep Learning Container License
- **Description:** Official NVIDIA CUDA runtime and development images.

---

## Python Libraries

### vLLM
- **Source:** https://github.com/vllm-project/vllm
- **License:** Apache License 2.0
- **Description:** High-throughput and memory-efficient inference and serving engine for LLMs.

### PyTorch
- **Source:** https://github.com/pytorch/pytorch
- **License:** BSD-3-Clause License
- **Description:** Open-source machine learning framework.

### Transformers (Hugging Face)
- **Source:** https://github.com/huggingface/transformers
- **License:** Apache License 2.0
- **Description:** State-of-the-art machine learning library for PyTorch.

---

## Additional References

### AWS Distributed Training Samples
- **Source:** https://github.com/aws-samples/awsome-distributed-training
- **License:** MIT-0 License
- **Description:** Reference implementations for distributed training on AWS.

---

## License Summary

| Component | License |
|-----------|---------|
| NVIDIA Dynamo | Apache-2.0 |
| NCCL | BSD-3-Clause |
| NIXL | Apache-2.0 |
| TensorRT-LLM | Apache-2.0 |
| UCX | BSD-3-Clause |
| Libfabric | BSD-2-Clause |
| OpenMPI | BSD-3-Clause |
| AWS EFA Installer | Apache-2.0 |
| AWS OFI NCCL | Apache-2.0 |
| vLLM | Apache-2.0 |
| PyTorch | BSD-3-Clause |
| Transformers | Apache-2.0 |

---

## Disclaimer

This project is provided "as is" without warranty of any kind. The use of third-party components is subject to their respective licenses. Users are responsible for ensuring compliance with all applicable licenses when using this software.

For questions about licensing or attribution, please open an issue in the repository.

---

**Last Updated:** November 2025
