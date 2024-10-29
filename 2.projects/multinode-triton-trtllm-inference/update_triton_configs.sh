#!/bin/bash

# Check if PATH_TO_TOKENIZER and PATH_TO_ENGINES are set
if [ -z "$PATH_TO_TOKENIZER" ] || [ -z "$PATH_TO_ENGINE" ]; then
    echo "Error: PATH_TO_TOKENIZER and PATH_TO_ENGINES must be set"
    echo "Usage: export PATH_TO_TOKENIZER=/path/to/tokenizer; export PATH_TO_ENGINES=/path/to/engines; bash update_triton_configs.sh"
    exit 1
else
    echo "PATH_TO_TOKENIZER is set to '$PATH_TO_TOKENIZER', and PATH_TO_ENGINE is set to '$PATH_TO_ENGINE'"    
fi    

# Change the preprocessing config.pbtxt
python3 tools/fill_template.py -i triton_model_repo/preprocessing/config.pbtxt tokenizer_dir:${PATH_TO_TOKENIZER},tokenizer_type:llama,triton_max_batch_size:8,preprocessing_instance_count:1

# Change the tensorrt_llm config.pbtxt
python3 tools/fill_template.py -i triton_model_repo/tensorrt_llm/config.pbtxt triton_backend:tensorrtllm,triton_max_batch_size:8,decoupled_mode:True,max_beam_width:1,engine_dir:${PATH_TO_ENGINE},enable_kv_cache_reuse:False,batching_strategy:inflight_batching,max_queue_delay_microseconds:0

# Change the postprocessing config.pbtxt
python3 tools/fill_template.py -i triton_model_repo/postprocessing/config.pbtxt tokenizer_dir:${PATH_TO_TOKENIZER},tokenizer_type:llama,triton_max_batch_size:8,postprocessing_instance_count:1

# Change the ensemble config.pbtxt
python3 tools/fill_template.py -i triton_model_repo/ensemble/config.pbtxt triton_max_batch_size:8

echo "All Triton configurations have been updated."