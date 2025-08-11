#!/usr/bin/env python3
import os
import sys

import aws_cdk as cdk

from cdk.cdk_stack import CdkStack
from cdk.config_loader import ConfigurationLoader


app = cdk.App()

# Parse command-line arguments for --config-file
config_file = None
for i, arg in enumerate(sys.argv):
    if arg == '--config-file' and i + 1 < len(sys.argv):
        config_file = sys.argv[i + 1]
        break

# Also check for config_file in CDK context
if not config_file:
    config_file = app.node.try_get_context("config_file")

# Load configuration if specified
config_loader = ConfigurationLoader(config_file)

# If configuration file is specified, load and apply it
if config_file:
    # Get current context parameters from CDK
    context_params = {}
    
    # Collect all known context parameters
    known_params = [
        'model_id', 'instance_type', 'router_ip',
        'tokenizer_path', 'tokenizer_mode', 'skip_tokenizer_init',
        'load_format', 'trust_remote_code', 'dtype', 'kv_cache_dtype',
        'quantization_param_path', 'quantization', 'context_length',
        'device', 'served_model_name', 'chat_template', 'is_embedding',
        'revision', 'mem_fraction_static', 'max_running_requests',
        'max_total_tokens', 'chunked_prefill_size', 'max_prefill_tokens',
        'schedule_policy', 'schedule_conservativeness', 'cpu_offload_gb',
        'prefill_only_one_req', 'tensor_parallel_size', 'stream_interval',
        'random_seed', 'constrained_json_whitespace_pattern', 'watchdog_timeout',
        'download_dir', 'base_gpu_id', 'log_level', 'log_level_http',
        'log_requests', 'show_time_cost', 'enable_metrics', 'decode_log_interval',
        'api_key', 'file_storage_pth', 'enable_cache_report', 'data_parallel_size',
        'load_balance_method', 'expert_parallel_size', 'dist_init_addr',
        'nnodes', 'node_rank', 'json_model_override_args', 'lora_paths',
        'max_loras_per_batch', 'attention_backend', 'sampling_backend',
        'grammar_backend', 'speculative_algorithm', 'speculative_draft_model_path',
        'speculative_num_steps', 'speculative_num_draft_tokens', 'speculative_eagle_topk',
        'enable_double_sparsity', 'ds_channel_config_path', 'ds_heavy_channel_num',
        'ds_heavy_token_num', 'ds_heavy_channel_type', 'ds_sparse_decode_threshold',
        'disable_radix_cache', 'disable_jump_forward', 'disable_cuda_graph',
        'disable_cuda_graph_padding', 'disable_outlines_disk_cache',
        'disable_custom_all_reduce', 'disable_mla', 'disable_overlap_schedule',
        'enable_mixed_chunk', 'enable_dp_attention', 'enable_ep_moe',
        'enable_torch_compile', 'torch_compile_max_bs', 'cuda_graph_max_bs',
        'cuda_graph_bs', 'torchao_config', 'enable_nan_detection',
        'enable_p2p_check', 'triton_attention_reduce_in_fp32',
        'triton_attention_num_kv_splits', 'num_continuous_decode_steps',
        'delete_ckpt_after_loading', 'enable_memory_saver', 'allow_auto_truncate',
        'enable_custom_logit_processor'
    ]
    
    for param in known_params:
        value = app.node.try_get_context(param)
        if value is not None:
            context_params[param] = value

    # Get merged configuration
    configuration = config_loader.get_configuration(context_params)

    # Convert configuration to context parameters and apply
    if configuration:
        params = config_loader.to_context_params(configuration)
        
        # Apply parameters to app context
        for key, value in params.items():
            if value is not None:
                app.node.set_context(key, value)

# Get stack name from context or use default with timestamp
stack_name = app.node.try_get_context("stack_name") or f"SGLangStack-{int(__import__('time').time())}"

CdkStack(app, stack_name,
    # If you don't specify 'env', this stack will be environment-agnostic.
    # Account/Region-dependent features and context lookups will not work,
    # but a single synthesized template can be deployed anywhere.

    # Uncomment the next line to specialize this stack for the AWS Account
    # and Region that are implied by the current CLI configuration.

    env=cdk.Environment(account=os.getenv('CDK_DEFAULT_ACCOUNT'), region=os.getenv('CDK_DEFAULT_REGION')),

    # Uncomment the next line if you know exactly what Account and Region you
    # want to deploy the stack to. */

    # For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html
    )

app.synth()
