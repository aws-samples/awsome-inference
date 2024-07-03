#!/bin/bash
# Author: Aman Shanbhag
# Description: This script allows the user to run local inference via TRT-LLM.

# pip3 install flask
# pip install flask
echo "Running healthcheck server"
chmod +x healthcheck.py
python3 healthcheck.py &

# TODO: Move the HF cloning into 2.install_trtllm_and_triton.sh

HF_USERNAME="username"
HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
MODEL_NAME="Meta-Llama-3-8B-Instruct"
MODEL_DIR="meta-llama/Meta-Llama-3-8B-Instruct"

# DO NOT MOVE THIS
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-12.1/compat

# Can be moved to 2.install_trtllm_and_triton.sh
pip3 install torch
pip3 install --no-cache-dir --extra-index-url https://pypi.nvidia.com tensorrt-llm  # NEW LINE

# pip3 install -r /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/TensorRT-LLM/examples/llama/requirements.txt --extra-index-url https://pypi.ngc.nvidia.com

# Can be moved to 2.install_trtllm_and_triton.sh

# Clone the Hugging Face model repository (https://huggingface.co/meta-llama/Meta-Llama-3-8B)
# Note: This requires you to agree to some terms and conditions set forth by HF + Meta. 
# To clone this repository, make sure you have a HF access token of type WRITE.
REPO_NAME="https://${HF_USERNAME}:${HF_TOKEN}@huggingface.co/${MODEL_DIR}"
echo "Cloning ${REPO_NAME}..."
mkdir -p /tensorrt/models && cd /tensorrt/models && git clone $REPO_NAME


# DO NOT MOVE 

# Step 1: Run the convert_checkpoint script to convert the model to TRT-LLM format.
# Build the Llama 8B model using a single GPU and FP16.
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tensorrt_llm/examples/llama/convert_checkpoint.py \
        --model_dir /tensorrt/models/${MODEL_NAME} \
        --output_dir /tensorrt/tensorrt-models/${MODEL_NAME}/0.10.0.dev2024043000/trt-checkpoints/fp16/1-gpu/ \
        --dtype float16

# DO NOT MOVE

# Step 2: Create an engine based on the converted checkpoint above.
trtllm-build --checkpoint_dir /tensorrt/tensorrt-models/${MODEL_NAME}/0.10.0.dev2024043000/trt-checkpoints/fp16/1-gpu/ \
    --output_dir /tensorrt/tensorrt-models/${MODEL_NAME}/0.10.0.dev2024043000/trt-engines/fp16/1-gpu/ \
    --gpt_attention_plugin float16 \
    --gemm_plugin float16

# ONLY HERE FOR DEBUGGING PURPOSES... CAN BE REMOVED COMPLETELY LATER

# Step 3: Run inference on the engine.    
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tensorrt_llm/examples/run.py \
    --engine_dir=/tensorrt/tensorrt-models/${MODEL_NAME}/0.10.0.dev2024043000/trt-engines/fp16/1-gpu/ \
    --max_output_len 100 \
    --tokenizer_dir /tensorrt/models/${MODEL_NAME} \
    --input_text "Explain the black hole to me as if I were a child."

# MAIN APPLICATION LOGIC -- DO NOT MOVE
mkdir -p /tensorrt/triton-repos/Meta-Llama-3-8B-Instruct/
cp -r /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/all_models/inflight_batcher_llm/* /tensorrt/triton-repos/Meta-Llama-3-8B-Instruct/
# Use the fill_template.py script to make changes to the config.pbtxt file
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tools/fill_template.py -i /tensorrt/triton-repos/Meta-Llama-3-8B-Instruct/preprocessing/config.pbtxt tokenizer_dir:/tensorrt/models/Meta-Llama-3-8B-Instruct,tokenizer_type:llama,triton_max_batch_size:64,preprocessing_instance_count:1
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tools/fill_template.py -i /tensorrt/triton-repos/Meta-Llama-3-8B-Instruct/postprocessing/config.pbtxt tokenizer_dir:/tensorrt/models/Meta-Llama-3-8B-Instruct,tokenizer_type:llama,triton_max_batch_size:64,postprocessing_instance_count:1
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tools/fill_template.py -i /tensorrt/triton-repos/Meta-Llama-3-8B-Instruct/tensorrt_llm_bls/config.pbtxt triton_max_batch_size:64,decoupled_mode:False,bls_instance_count:1,accumulate_tokens:False
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tools/fill_template.py -i /tensorrt/triton-repos/Meta-Llama-3-8B-Instruct/ensemble/config.pbtxt triton_max_batch_size:64
python3 /tensorrt/0.10.0.dev2024043000/tensorrtllm_backend/tools/fill_template.py -i /tensorrt/triton-repos/Meta-Llama-3-8B-Instruct/tensorrt_llm/config.pbtxt triton_max_batch_size:64,decoupled_mode:False,max_beam_width:1,engine_dir:/tensorrt/tensorrt-models/Meta-Llama-3-8B-Instruct/0.10.0.dev2024043000/trt-engines/fp16/1-gpu,max_tokens_in_paged_kv_cache:2560,max_attention_window_size:2560,kv_cache_free_gpu_mem_fraction:0.9,exclude_input_in_output:True,enable_kv_cache_reuse:False,batching_strategy:inflight_batching,max_queue_delay_microseconds:600

# Start the Triton Server
tritonserver --model-repository=/tensorrt/triton-repos/Meta-Llama-3-8B-Instruct --model-control-mode=explicit --load-model=preprocessing --load-model=postprocessing --load-model=tensorrt_llm --load-model=tensorrt_llm_bls --load-model=ensemble --log-verbose=2 --log-info=1 --log-warning=1 --log-error=1