from aws_cdk import Stack, CfnParameter
from constructs import Construct
from .logs import Logs
from .image_builder import ImageBuilder
from .router import Router 
from .workers import Workers
from .vpc import Vpc
from .connections import NetworkConnections

class CdkStack(Stack):
    """Main CDK stack that sets up infrastructure for a distributed ML inference system.
    
    This stack creates:
    - A VPC for network isolation
    - CloudWatch logs for monitoring
    - An EC2 Image Builder pipeline for creating ML-optimized AMIs
    - An Auto Scaling Group of worker nodes that run the ML models
    - A router instance that load balances requests across workers
    - Security group rules to allow communication between components
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get model ID and instance type from context
        model_id = self.node.try_get_context("model_id") or "Valdemardi/DeepSeek-R1-Distill-Qwen-32B-AWQ"
        instance_type = self.node.try_get_context("instance_type") or "g6e.xlarge"
        router_ip = self.node.try_get_context("router_ip") or "10.0.0.100"

        # Get optional SGLang worker arguments from context
        sglang_args = {
            "tokenizer_path": self.node.try_get_context("tokenizer_path"),
            "tokenizer_mode": self.node.try_get_context("tokenizer_mode"),
            "skip_tokenizer_init": self.node.try_get_context("skip_tokenizer_init"),
            "load_format": self.node.try_get_context("load_format"),
            "trust_remote_code": self.node.try_get_context("trust_remote_code"),
            "dtype": self.node.try_get_context("dtype"),
            "kv_cache_dtype": self.node.try_get_context("kv_cache_dtype"),
            "quantization_param_path": self.node.try_get_context("quantization_param_path"),
            "quantization": self.node.try_get_context("quantization"),
            "context_length": self.node.try_get_context("context_length"),
            "device": self.node.try_get_context("device"),
            "served_model_name": self.node.try_get_context("served_model_name"),
            "chat_template": self.node.try_get_context("chat_template"),
            "is_embedding": self.node.try_get_context("is_embedding"),
            "revision": self.node.try_get_context("revision"),
            "mem_fraction_static": self.node.try_get_context("mem_fraction_static"),
            "max_running_requests": self.node.try_get_context("max_running_requests"),
            "max_total_tokens": self.node.try_get_context("max_total_tokens"),
            "chunked_prefill_size": self.node.try_get_context("chunked_prefill_size"),
            "max_prefill_tokens": self.node.try_get_context("max_prefill_tokens"),
            "schedule_policy": self.node.try_get_context("schedule_policy"),
            "schedule_conservativeness": self.node.try_get_context("schedule_conservativeness"),
            "cpu_offload_gb": self.node.try_get_context("cpu_offload_gb"),
            "prefill_only_one_req": self.node.try_get_context("prefill_only_one_req"),
            "tp-size": self.node.try_get_context("tp-size"),
            "stream_interval": self.node.try_get_context("stream_interval"),
            "random_seed": self.node.try_get_context("random_seed"),
            "constrained_json_whitespace_pattern": self.node.try_get_context("constrained_json_whitespace_pattern"),
            "watchdog_timeout": self.node.try_get_context("watchdog_timeout"),
            "download_dir": self.node.try_get_context("download_dir"),
            "base_gpu_id": self.node.try_get_context("base_gpu_id"),
            "log_level": self.node.try_get_context("log_level"),
            "log_level_http": self.node.try_get_context("log_level_http"),
            "log_requests": self.node.try_get_context("log_requests"),
            "show_time_cost": self.node.try_get_context("show_time_cost"),
            "enable_metrics": self.node.try_get_context("enable_metrics"),
            "decode_log_interval": self.node.try_get_context("decode_log_interval"),
            "api_key": self.node.try_get_context("api_key"),
            "file_storage_pth": self.node.try_get_context("file_storage_pth"),
            "enable_cache_report": self.node.try_get_context("enable_cache_report"),
            "data_parallel_size": self.node.try_get_context("data_parallel_size"),
            "load_balance_method": self.node.try_get_context("load_balance_method"),
            "expert_parallel_size": self.node.try_get_context("expert_parallel_size"),
            "dist_init_addr": self.node.try_get_context("dist_init_addr"),
            "nnodes": self.node.try_get_context("nnodes"),
            "node_rank": self.node.try_get_context("node_rank"),
            "json_model_override_args": self.node.try_get_context("json_model_override_args"),
            "lora_paths": self.node.try_get_context("lora_paths"),
            "max_loras_per_batch": self.node.try_get_context("max_loras_per_batch"),
            "attention_backend": self.node.try_get_context("attention_backend"),
            "sampling_backend": self.node.try_get_context("sampling_backend"),
            "grammar_backend": self.node.try_get_context("grammar_backend"),
            "speculative_algorithm": self.node.try_get_context("speculative_algorithm"),
            "speculative_draft_model_path": self.node.try_get_context("speculative_draft_model_path"),
            "speculative_num_steps": self.node.try_get_context("speculative_num_steps"),
            "speculative_num_draft_tokens": self.node.try_get_context("speculative_num_draft_tokens"),
            "speculative_eagle_topk": self.node.try_get_context("speculative_eagle_topk"),
            "enable_double_sparsity": self.node.try_get_context("enable_double_sparsity"),
            "ds_channel_config_path": self.node.try_get_context("ds_channel_config_path"),
            "ds_heavy_channel_num": self.node.try_get_context("ds_heavy_channel_num"),
            "ds_heavy_token_num": self.node.try_get_context("ds_heavy_token_num"),
            "ds_heavy_channel_type": self.node.try_get_context("ds_heavy_channel_type"),
            "ds_sparse_decode_threshold": self.node.try_get_context("ds_sparse_decode_threshold"),
            "disable_radix_cache": self.node.try_get_context("disable_radix_cache"),
            "disable_jump_forward": self.node.try_get_context("disable_jump_forward"),
            "disable_cuda_graph": self.node.try_get_context("disable_cuda_graph"),
            "disable_cuda_graph_padding": self.node.try_get_context("disable_cuda_graph_padding"),
            "disable_outlines_disk_cache": self.node.try_get_context("disable_outlines_disk_cache"),
            "disable_custom_all_reduce": self.node.try_get_context("disable_custom_all_reduce"),
            "disable_mla": self.node.try_get_context("disable_mla"),
            "disable_overlap_schedule": self.node.try_get_context("disable_overlap_schedule"),
            "enable_mixed_chunk": self.node.try_get_context("enable_mixed_chunk"),
            "enable_dp_attention": self.node.try_get_context("enable_dp_attention"),
            "enable_ep_moe": self.node.try_get_context("enable_ep_moe"),
            "enable_torch_compile": self.node.try_get_context("enable_torch_compile"),
            "torch_compile_max_bs": self.node.try_get_context("torch_compile_max_bs"),
            "cuda_graph_max_bs": self.node.try_get_context("cuda_graph_max_bs"),
            "cuda_graph_bs": self.node.try_get_context("cuda_graph_bs"),
            "torchao_config": self.node.try_get_context("torchao_config"),
            "enable_nan_detection": self.node.try_get_context("enable_nan_detection"),
            "enable_p2p_check": self.node.try_get_context("enable_p2p_check"),
            "triton_attention_reduce_in_fp32": self.node.try_get_context("triton_attention_reduce_in_fp32"),
            "triton_attention_num_kv_splits": self.node.try_get_context("triton_attention_num_kv_splits"),
            "num_continuous_decode_steps": self.node.try_get_context("num_continuous_decode_steps"),
            "delete_ckpt_after_loading": self.node.try_get_context("delete_ckpt_after_loading"),
            "enable_memory_saver": self.node.try_get_context("enable_memory_saver"),
            "allow_auto_truncate": self.node.try_get_context("allow_auto_truncate"),
            "enable_custom_logit_processor": self.node.try_get_context("enable_custom_logit_processor")
        }

        # Filter out None values and convert to CLI arguments
        extra_args = []
        for key, value in sglang_args.items():
            if value is not None:
                arg_key = key.replace('_', '-')
                if isinstance(value, bool):
                    if value:
                        extra_args.append(f"--{arg_key}")
                else:
                    extra_args.append(f"--{arg_key}")
                    extra_args.append(str(value))
        extra_args_str = ' '.join(extra_args)

        # Create VPC for network isolation
        vpc = Vpc(self, "VPC")
        
        # Set up CloudWatch logging
        logs = Logs(self, "Logs")
        
        # Create Image to bootstrap an AMI for fast worker startup
        image_builder = ImageBuilder(self, "ImageBuilder", vpc, logs, model_id, instance_type=instance_type)
        # Create worker Auto Scaling Group and router instance
        workers = Workers(self, "Workers", vpc, image_builder, instance_type=instance_type, extra_args=extra_args_str, router_ip=router_ip)
        router = Router(self, "Router", vpc, logs, router_ip=router_ip)
        
        # Configure security group rules between components
        connections = NetworkConnections(self, "NetworkConnections", workers, router)
