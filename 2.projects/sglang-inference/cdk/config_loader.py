"""
Configuration loader for SGLang CDK deployment.

This module handles loading and validating configuration files,
merging with CLI context parameters, and providing a unified
configuration object to the CDK stack.
"""
import json
import os
from pathlib import Path
from typing import Dict, Any, Optional
import yaml


class ConfigurationLoader:
    """Loads and manages SGLang CDK configurations."""
    
    def __init__(self, config_file: Optional[str] = None):
        """
        Initialize the configuration loader.
        
        Args:
            config_file: Path to YAML configuration file
        """
        self.config_file = config_file
        self.config = {}
        self.schema = None
        
    def load_schema(self) -> Dict[str, Any]:
        """Load the JSON schema for configuration validation."""
        schema_path = Path(__file__).parent.parent / "configs" / "schema" / "sglang-config-v1.0.json"
        if schema_path.exists():
            with open(schema_path, 'r') as f:
                self.schema = json.load(f)
        return self.schema
    
    def load_config_file(self) -> Dict[str, Any]:
        """Load configuration from YAML file."""
        if not self.config_file:
            return {}
            
        config_path = Path(self.config_file)
        if not config_path.exists():
            raise FileNotFoundError(f"Configuration file not found: {self.config_file}")
            
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
            
        return config
    
    def validate_config(self, config: Dict[str, Any]) -> bool:
        """
        Validate configuration against schema.
        
        Note: This is a basic validation. For production use,
        consider using jsonschema library for full validation.
        """
        if not config:
            return True
            
        # Check required fields
        required_fields = ['version', 'model', 'instances']
        for field in required_fields:
            if field not in config:
                raise ValueError(f"Required field '{field}' missing in configuration")
                
        # Validate version
        if config.get('version') != '1.0':
            raise ValueError(f"Unsupported configuration version: {config.get('version')}")
            
        # Validate model
        if 'id' not in config.get('model', {}):
            raise ValueError("Model ID is required")
            
        # Validate instances
        if 'workers' not in config.get('instances', {}):
            raise ValueError("Worker instances configuration is required")
            
        if 'type' not in config['instances']['workers']:
            raise ValueError("Worker instance type is required")
            
        return True
    
    def merge_configurations(self, file_config: Dict[str, Any], context_params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Merge file configuration with CDK context parameters.
        Context parameters take precedence over file configuration.
        
        Args:
            file_config: Configuration loaded from file
            context_params: Parameters from CDK context
            
        Returns:
            Merged configuration dictionary
        """
        # Start with file configuration
        merged = file_config.copy() if file_config else {}
        
        # Map context parameters to configuration structure
        if context_params:
            # Model configuration
            if 'model_id' in context_params:
                if 'model' not in merged:
                    merged['model'] = {}
                merged['model']['id'] = context_params['model_id']
                
            # Instance configuration
            if 'instance_type' in context_params:
                if 'instances' not in merged:
                    merged['instances'] = {}
                if 'workers' not in merged['instances']:
                    merged['instances']['workers'] = {}
                merged['instances']['workers']['type'] = context_params['instance_type']
                
            if 'router_ip' in context_params:
                if 'instances' not in merged:
                    merged['instances'] = {}
                if 'router' not in merged['instances']:
                    merged['instances']['router'] = {}
                merged['instances']['router']['ip'] = context_params['router_ip']
                
            # SGLang parameters - map all other context parameters
            sglang_params = {}
            for key, value in context_params.items():
                if key not in ['model_id', 'instance_type', 'router_ip'] and value is not None:
                    sglang_params[key] = value
                    
            if sglang_params:
                if 'sglang' not in merged:
                    merged['sglang'] = {}
                merged['sglang'].update(sglang_params)
                
        return merged
    
    def get_configuration(self, context_params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Get the complete configuration by loading file and merging with context.
        
        Args:
            context_params: CDK context parameters
            
        Returns:
            Complete configuration dictionary
        """
        # Load configuration from file if specified
        file_config = self.load_config_file() if self.config_file else {}
        
        # Merge with context parameters
        config = self.merge_configurations(file_config, context_params or {})
        
        # Validate final configuration
        if config:
            self.validate_config(config)
            
        return config
    
    def to_context_params(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert configuration to CDK context parameters format.
        
        This is used to maintain backward compatibility with existing
        CDK stack implementation.
        
        Args:
            config: Configuration dictionary
            
        Returns:
            Dictionary of context parameters
        """
        params = {}
        
        # Model parameters
        if 'model' in config:
            if 'id' in config['model']:
                params['model_id'] = config['model']['id']
            if 'revision' in config['model']:
                params['revision'] = config['model']['revision']
                
        # Instance parameters
        if 'instances' in config:
            if 'workers' in config['instances']:
                worker_config = config['instances']['workers']
                if 'type' in worker_config:
                    params['instance_type'] = worker_config['type']
                    
            if 'router' in config['instances']:
                router_config = config['instances']['router']
                if 'ip' in router_config:
                    params['router_ip'] = router_config['ip']
                    
        # SGLang parameters
        if 'sglang' in config and config['sglang'] is not None:
            params.update(config['sglang'])
            
        return params
    
    @staticmethod
    def get_default_config() -> Dict[str, Any]:
        """Get default configuration values."""
        return {
            'version': '1.0',
            'model': {
                'id': 'openai/gpt-oss-20b'
            },
            'instances': {
                'workers': {
                    'type': 'g6e.xlarge',
                    'min_capacity': 1,
                    'max_capacity': 3,
                    'desired_capacity': 1
                },
                'router': {
                    'type': 't3.medium',
                    'ip': '10.0.0.100'
                }
            }
        }