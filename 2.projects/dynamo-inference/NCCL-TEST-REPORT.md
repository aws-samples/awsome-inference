# NCCL Test on H100 Cluster - Report

## Date: November 26, 2025

## Summary

Successfully built and deployed an H100-optimized Docker image with EFA support for running NCCL tests on AWS HyperPod P5 instances. The image includes all necessary components for high-performance GPU-to-GPU communication testing.

## Accomplishments

### 1. Docker Image Build and Push
- **Built H100-optimized image**: `aws-efa-dynamo-h100:latest` (8.87GB)
- **Image ID**: 0403aabd5859
- **Successfully pushed to ECR**: `public.ecr.aws/v9l4g5s4/aws-efa-dynamo-h100:latest`

### 2. Build Script Enhancement
- Updated `/home/ubuntu/dynamo-final/build.sh` with:
  - GPU architecture support (`-a` flag)
  - Automatic GPU suffix for image names (e.g., `-h100`, `-a100`, `-a10`)
  - Non-interactive ECR push functionality
  - Automatic repository creation
  - ECR authentication for both public and private registries
  - Prerequisites checking (Docker, AWS CLI, credentials)

### 3. Image Components (H100-optimized)
The built image includes:
- **CUDA 13.0.0** runtime and development libraries
- **EFA installer 1.43.1** with OpenMPI support
- **Libfabric 2.3.0** with EFA provider
- **UCX 1.19.0** with EFA and CUDA support
- **NCCL 2.27.5** optimized for SM90 (H100) architecture
- **AWS OFI NCCL 1.17.1** for EFA integration
- **NIXL 0.7.1** for GPU-direct transfers
- **gdrcopy 2.4**
- **etcd-cpp-apiv3 0.15.3**
- **AWS SDK C++ 1.11.379**
- **NCCL tests** compiled with MPI support

### 4. NCCL Test Deployment
- Created NCCL test YAML: `/home/ubuntu/dynamo-final/nccl-test-h100.yaml`
- Configured for P5.48xlarge instances with 8x H100 GPUs
- Includes proper EFA environment variables:
  - FI_PROVIDER=efa
  - FI_EFA_USE_DEVICE_RDMA=1
  - NCCL_PROTO=Simple
  - NCCL_ALGO=Ring
  - NCCL_MIN_NCHANNELS=8

### 5. Documentation Updates
- Updated `/home/ubuntu/dyno_reinvent/README.md` with:
  - Comprehensive build instructions
  - GPU architecture support documentation
  - Build script usage examples
  - Automated ECR integration details
  - NVIDIA Dynamo disaggregated inference information

## Build Command Used
```bash
./build.sh -b efa -a 90 -r public.ecr.aws/v9l4g5s4 -p -t latest
```

## Test Deployment Command
```bash
kubectl apply -f /home/ubuntu/dynamo-final/nccl-test-h100.yaml
```

## Key Features

### GPU Architecture Support
- **SM75 (A10)**: Cost-effective inference
- **SM86 (A100)**: High-performance training
- **SM90 (H100)**: Latest generation, maximum performance

### Build Script Capabilities
- Build base EFA image alone or with backends
- Support for TensorRT-LLM and vLLM backends
- GPU-specific optimization with CUDA architecture targeting
- Automatic ECR repository management
- Non-interactive CI/CD pipeline support

## Test Configuration
The NCCL test is configured to run AllReduce performance tests with:
- Buffer sizes: 8MB to 1GB
- 8 GPUs (single node test)
- 20 iterations per size
- MPI launcher with proper EFA configuration

## Next Steps

1. **Monitor NCCL Test Results**: Once pods are scheduled, monitor the test output for performance metrics
2. **Multi-node Testing**: Extend to multi-node tests across P5 instances
3. **Backend Integration**: Build and test TensorRT-LLM and vLLM backend images
4. **Performance Tuning**: Optimize NCCL parameters based on test results
5. **Production Deployment**: Deploy NVIDIA Dynamo for disaggregated inference

## Technical Notes

### Image Pull Issue Resolution
- Initially encountered image pull errors due to ECR propagation delay
- Successfully pushed image to public ECR repository
- Image now available at: `public.ecr.aws/v9l4g5s4/aws-efa-dynamo-h100:latest`

### Build Optimizations
- Multi-stage Docker build reduces final image size
- Separate build and runtime stages
- Compiled NCCL tests with MPI support in build stage
- Runtime stage includes only necessary libraries

### EFA Configuration
- Properly configured for P5.48xlarge instances
- 400 Gbps EFA networking support
- GPU-direct communication via NIXL
- Optimized for H100 GPU architecture

## Repository Locations
- **Build Directory**: `/home/ubuntu/dynamo-final/`
- **Original Dockerfiles**: `/home/ubuntu/dyno_reinvent/`
- **Build Script**: `/home/ubuntu/dynamo-final/build.sh`
- **Test YAML**: `/home/ubuntu/dynamo-final/nccl-test-h100.yaml`

---

**Report Generated**: November 26, 2025, 01:47 UTC