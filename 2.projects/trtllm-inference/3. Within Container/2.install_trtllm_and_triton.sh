#!/bin/bash
# Author: Aman Shanbhag
# Description: This script will install TensorRT-LLM and the NVIDIA Triton Inference Server

TRTLLM_STABLE_VERSION=0.10.0.dev2024043000
TRITON_DIR="/tensorrt/$TRTLLM_STABLE_VERSION"
echo "Creating directory $TRITON_DIR"

# Installing the Triton Inference Server Backend for TRT-LLM. Hardcoding to debug.
[ ! -d "/tensorrt/0.10.0.dev2024043000" ] && mkdir -p "/tensorrt/0.10.0.dev2024043000"
cd "/tensorrt/0.10.0.dev2024043000"
git clone https://github.com/triton-inference-server/tensorrtllm_backend.git --progress --verbose

# Update the submodules, as per https://github.com/triton-inference-server/tensorrtllm_backend?tab=readme-ov-file
cd "/tensorrt/0.10.0.dev2024043000/tensorrtllm_backend"
git submodule update --init --recursive
git-lfs install
git-lfs pull

# Installing TensorRT-LLM and all other requirements to build and run engines
cd "/tensorrt/0.10.0.dev2024043000/tensorrtllm_backend"
apt-get update && apt-get -y install python3.10 python3-pip openmpi-bin libopenmpi-dev git
git clone https://github.com/NVIDIA/TensorRT-LLM.git
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-12.1/compat
pip3 install -r TensorRT-LLM/examples/llama/requirements.txt 
pip3 install flask
pip install flask
python3 -c "import flask"	# Check installation
# pip3 install tensorrt_llm=="0.10.0.dev2024043000" -U --extra-index-url https://pypi.nvidia.com
python3 -c "import tensorrt_llm"	# Check installation