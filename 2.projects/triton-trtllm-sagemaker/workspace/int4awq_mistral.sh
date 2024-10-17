echo "Git cloning the TRT-LLM Backend repo from GitHub and setting it up..."
git clone https://github.com/triton-inference-server/tensorrtllm_backend.git -b v0.13.0 
cd tensorrtllm_backend
git lfs install
git submodule update --init --recursive
cd /workspace

rsync -av --exclude='tensorrt_llm_bls' tensorrtllm_backend/all_models/inflight_batcher_llm/ triton_model_repo/

echo "Starting the process of building TRT-LLM engines..."
export HF_MODEL_PATH=/workspace/hf_models/
export UNIFIED_CKPT_PATH=/workspace/ckpt/
export ENGINE_PATH=/workspace/triton_model_repo/tensorrt_llm/1/engines/
[ -d ${HF_MODEL_PATH}/.cache ] && rm -rf ${HF_MODEL_PATH}/.cache
rsync -av --exclude="*.ot" --exclude="*onnx" --exclude="*.bin" --exclude="*.safetensors" --exclude="*.h5" --exclude="*.msgpack" ${HF_MODEL_PATH} /workspace/triton_model_repo/tensorrt_llm/1/hf_models/
export SAGEMAKER_ENGINE_PATH=/opt/ml/model/tensorrt_llm/1/engines
export SAGEMAKER_TOKENIZER_PATH=/opt/ml/model/tensorrt_llm/1/hf_models/

TP_SIZE=1
MAX_BEAM_WIDTH=2
MAX_BATCH_SIZE=32
MAX_INPUT_LEN=1024
MAX_OUTPUT_LEN=201

echo "Quantizing model checkpoint to INT4 AWQ TRT-LLM format.."

pip install setuptools                             
python3 tensorrtllm_backend/tensorrt_llm/examples/quantization/quantize.py \
                               --model_dir ${HF_MODEL_PATH} \
                               --dtype float16 \
                               --qformat int4_awq \
                               --awq_block_size 128 \
                               --output_dir ${UNIFIED_CKPT_PATH} \
                               --calib_size 32
                             

echo "Building TRT-LLM engine.."
trtllm-build --checkpoint_dir ${UNIFIED_CKPT_PATH} \
             --output_dir ${ENGINE_PATH} \
             --gemm_plugin auto \
             --max_beam_width ${MAX_BEAM_WIDTH} 


echo "Finished building TRT-LLM engines..."

echo "Preparing Triton Model Repository for the model..."
python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/tensorrt_llm/config.pbtxt triton_backend:tensorrtllm,triton_max_batch_size:${MAX_BATCH_SIZE},decoupled_mode:False,max_beam_width:${MAX_BEAM_WIDTH},engine_dir:${SAGEMAKER_ENGINE_PATH},kv_cache_free_gpu_mem_fraction:0.95,exclude_input_in_output:True,enable_kv_cache_reuse:False,batching_strategy:inflight_fused_batching,max_queue_delay_microseconds:0,enable_chunked_context:False,max_queue_size:0

python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/preprocessing/config.pbtxt tokenizer_dir:${SAGEMAKER_TOKENIZER_PATH},triton_max_batch_size:${MAX_BATCH_SIZE},preprocessing_instance_count:1

python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/postprocessing/config.pbtxt tokenizer_dir:${SAGEMAKER_TOKENIZER_PATH},triton_max_batch_size:${MAX_BATCH_SIZE},postprocessing_instance_count:1

python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/ensemble/config.pbtxt triton_max_batch_size:${MAX_BATCH_SIZE}

echo "Finished preparing Triton Model Repository for the model..."
