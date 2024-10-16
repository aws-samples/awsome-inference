echo "Git cloning the TRT-LLM Backend repo from GitHub and setting it up..."
git clone https://github.com/triton-inference-server/tensorrtllm_backend.git -b v0.13.0 
cd tensorrtllm_backend
git lfs install
git submodule update --init --recursive
cd /workspace

rsync -av --exclude='tensorrt_llm_bls' tensorrtllm_backend/all_models/inflight_batcher_llm/ triton_model_repo/

echo "Starting the process of building TRT-LLM engines..."
export MODEL_TYPE="t5"
export HF_MODEL_PATH=/workspace/hf_models/
export UNIFIED_CKPT_PATH=/workspace/ckpt/
export ENGINE_PATH=/workspace/triton_model_repo/tensorrt_llm/1/engines/
rsync -av --exclude="*.ot" --exclude="*onnx" --exclude="*.bin" --exclude="*.safetensors" --exclude="*.h5" --exclude="*.msgpack" ${HF_MODEL_PATH} /workspace/triton_model_repo/tensorrt_llm/1/hf_models/
export SAGEMAKER_ENGINE_PATH=/opt/ml/model/tensorrt_llm/1/engines
export SAGEMAKER_TOKENIZER_PATH=/opt/ml/model/tensorrt_llm/1/hf_models/


INFERENCE_PRECISION=float16
TP_SIZE=1
MAX_BEAM_WIDTH=2
MAX_BATCH_SIZE=8
INPUT_LEN=1024
OUTPUT_LEN=201

echo "Converting to TRT-LLM checkpoint format...."

python3 tensorrtllm_backend/tensorrt_llm/examples/enc_dec/convert_checkpoint.py \
--model_type ${MODEL_TYPE} \
--model_dir ${HF_MODEL_PATH} \
--output_dir ${UNIFIED_CKPT_PATH} \
--dtype ${INFERENCE_PRECISION} \
--tp_size ${TP_SIZE}

if [ "$MODEL_TYPE" = "t5" ] || [ "$MODEL_TYPE" = "T5" ]; then
    echo "Building TRT-LLM engine for encoder..."
    trtllm-build --checkpoint_dir ${UNIFIED_CKPT_PATH}/encoder \
    --output_dir ${ENGINE_PATH}/encoder \
    --kv_cache_type disabled \
    --moe_plugin disable \
    --enable_xqa disable \
    --max_beam_width ${MAX_BEAM_WIDTH} \
    --max_input_len ${INPUT_LEN} \
    --max_batch_size ${MAX_BATCH_SIZE} \
    --gemm_plugin ${INFERENCE_PRECISION} \
    --bert_attention_plugin ${INFERENCE_PRECISION} \
    --gpt_attention_plugin ${INFERENCE_PRECISION} \
    --context_fmha disable # remove for BART
    
    echo "Building TRT-LLM engine for decoder..."
    trtllm-build --checkpoint_dir ${UNIFIED_CKPT_PATH}/decoder \
    --output_dir ${ENGINE_PATH}/decoder \
    --moe_plugin disable \
    --enable_xqa disable \
    --max_beam_width ${MAX_BEAM_WIDTH} \
    --max_batch_size ${MAX_BATCH_SIZE} \
    --gemm_plugin ${INFERENCE_PRECISION} \
    --bert_attention_plugin ${INFERENCE_PRECISION} \
    --gpt_attention_plugin ${INFERENCE_PRECISION} \
    --max_input_len 1 \
    --max_encoder_input_len ${INPUT_LEN} \
    --max_seq_len ${OUTPUT_LEN} \
    --context_fmha disable # remove for BART    

elif [ "$MODEL_TYPE" = "bart" ] || [ "$MODEL_TYPE" = "BART" ] || [ "$MODEL_TYPE" = "Bart" ]; then
    echo "Building TRT-LLM engine for encoder..."
    trtllm-build --checkpoint_dir ${UNIFIED_CKPT_PATH}/encoder \
    --output_dir ${ENGINE_PATH}/encoder \
    --paged_kv_cache disable \
    --moe_plugin disable \
    --enable_xqa disable \
    --max_beam_width ${MAX_BEAM_WIDTH} \
    --max_input_len ${INPUT_LEN} \
    --max_batch_size ${MAX_BATCH_SIZE} \
    --gemm_plugin ${INFERENCE_PRECISION} \
    --bert_attention_plugin ${INFERENCE_PRECISION} \
    --gpt_attention_plugin ${INFERENCE_PRECISION}

    echo "Building TRT-LLM engine for decoder..."
    trtllm-build --checkpoint_dir ${UNIFIED_CKPT_PATH}/decoder \
    --output_dir ${ENGINE_PATH}/decoder \
    --moe_plugin disable \
    --enable_xqa disable \
    --max_beam_width ${MAX_BEAM_WIDTH} \
    --max_batch_size ${MAX_BATCH_SIZE} \
    --gemm_plugin ${INFERENCE_PRECISION} \
    --bert_attention_plugin ${INFERENCE_PRECISION} \
    --gpt_attention_plugin ${INFERENCE_PRECISION} \
    --max_input_len 1 \
    --max_encoder_input_len ${INPUT_LEN} \
    --max_seq_len ${OUTPUT_LEN}

else
    echo "Invalid MODEL_TYPE provided. MODEL_TYPE needs to be either t5/T5 or bart/BART"
    exit 1
fi

echo "Finished building TRT-LLM engines..."

echo "Preparing Triton Model Repository for the model..."
python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/tensorrt_llm/config.pbtxt triton_backend:tensorrtllm,triton_max_batch_size:${MAX_BATCH_SIZE},decoupled_mode:False,max_beam_width:${MAX_BEAM_WIDTH},engine_dir:${SAGEMAKER_ENGINE_PATH}/decoder,encoder_engine_dir:${SAGEMAKER_ENGINE_PATH}/encoder,kv_cache_free_gpu_mem_fraction:0.45,exclude_input_in_output:True,enable_kv_cache_reuse:False,batching_strategy:inflight_fused_batching,max_queue_delay_microseconds:0,enable_chunked_context:False,max_queue_size:0

python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/preprocessing/config.pbtxt tokenizer_dir:${SAGEMAKER_TOKENIZER_PATH},triton_max_batch_size:${MAX_BATCH_SIZE},preprocessing_instance_count:1

python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/postprocessing/config.pbtxt tokenizer_dir:${SAGEMAKER_TOKENIZER_PATH},triton_max_batch_size:${MAX_BATCH_SIZE},postprocessing_instance_count:1

python3 tensorrtllm_backend/tools/fill_template.py -i triton_model_repo/ensemble/config.pbtxt triton_max_batch_size:${MAX_BATCH_SIZE}

echo "Finished preparing Triton Model Repository for the model..."
