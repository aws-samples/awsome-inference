# vLLM Expert Parallel Deployment

https://docs.vllm.ai/en/latest/serving/expert_parallel_deployment.html

1. Download NVSHMEM
```bash
wget https://developer.download.nvidia.com/compute/redist/nvshmem/3.3.9/source/nvshmem_src_cuda12-all-all-3.3.9.tar.gz && tar -xvf nvshmem_src_cuda12-all-all-3.3.9.tar.gz
```
2. Set environment variables
```bash
GDRCOPY_VERSION=v2.5.1
EFA_INSTALLER_VERSION=1.43.2
AWS_OFI_NCCL_VERSION=v1.16.3
NCCL_VERSION=v2.27.7-1
NCCL_TESTS_VERSION=v2.16.9
NVSHMEM_VERSION=3.3.9
PPLX_KERNELS_COMMIT=12cecfda252e4e646417ac263d96e994d476ee5d
DEEPGEMM_COMMIT=ea9c5d9270226c5dd7a577c212e9ea385f6ef048
DEEPEP_COMMIT=c18eabdebf1381978ff884d278f6083a6153be3f
TORCH_VERSION=2.7.1
VLLM_VERSION=0.10.1.1
TAG="vllm${VLLM_VERSION}-efa${EFA_INSTALLER_VERSION}-ofi${AWS_OFI_NCCL_VERSION}-nccl${NCCL_VERSION}-tests${NCCL_TESTS_VERSION}-nvshmem${NVSHMEM_VERSION}"
VLLM_EP_CONTAINER_IMAGE_NAME_TAG="vllm-ep:${TAG}"
```
3. Build the container image
```bash
docker build --progress=plain -f ./vllm-ep.Dockerfile \
       --build-arg="EFA_INSTALLER_VERSION=${EFA_INSTALLER_VERSION}" \
       --build-arg="AWS_OFI_NCCL_VERSION=${AWS_OFI_NCCL_VERSION}" \
       --build-arg="NCCL_VERSION=${NCCL_VERSION}" \
       --build-arg="NCCL_TESTS_VERSION=${NCCL_TESTS_VERSION}" \
       --build-arg="NVSHMEM_VERSION=${NVSHMEM_VERSION}" \
       --build-arg="PPLX_KERNELS_COMMIT=${PPLX_KERNELS_COMMIT}" \
       --build-arg="DEEPGEMM_COMMIT=${DEEPGEMM_COMMIT}" \
       --build-arg="DEEPEP_COMMIT=${DEEPEP_COMMIT}" \
       --build-arg="VLLM_VERSION=${VLLM_VERSION}" \
       --build-arg="TORCH_VERSION=${TORCH_VERSION}" \
       -t ${VLLM_EP_CONTAINER_IMAGE_NAME_TAG} \
       .
```
4. [Optional] Convert the container image to a SquashFS file
```bash
enroot import -o ./vllm-ep.sqsh dockerd://${VLLM_EP_CONTAINER_IMAGE_NAME_TAG}
```
5. Run the container on a single 8 GPU node
```bash
docker run --runtime nvidia --gpus all \
    -v "$HF_HOME":/root/.cache/huggingface \
    --env "HF_TOKEN=$HF_TOKEN" \
    -e VLLM_ALL2ALL_BACKEND=pplx \
    -e VLLM_USE_DEEP_GEMM=1 \
    -p 8000:8000 \
    --ipc=host \
    ${VLLM_EP_CONTAINER_IMAGE_NAME_TAG} \
    vllm serve deepseek-ai/DeepSeek-R1-0528 \
    --tensor-parallel-size 1 \
    --data-parallel-size 8 \
    --enable-expert-parallel
```
6. Expected logs:

FlashInfer Backend:
```
[topk_topp_sampler.py:50] Using FlashInfer for top-p & top-k sampling.
```

DeepGEMM Backend:
```
[fp8.py:512] Using DeepGemm kernels for Fp8MoEMethod.
```

PPLX Backend:
```
[cuda_communicator.py:81] Using PPLX all2all manager.
```
otherwise:
```
[cuda_communicator.py:77] Using naive all2all manager.
```
7. Benchmark
```
vllm bench serve \
    --model deepseek-ai/DeepSeek-R1-0528 \
    --dataset-name random \
    --random-input-len 128 \
    --random-output-len 128 \
    --num-prompts 10000 \
    --ignore-eos
```
