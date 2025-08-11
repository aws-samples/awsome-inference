"""
Unit tests for the configuration loader module.
"""
import pytest
import tempfile
import yaml
from pathlib import Path
from cdk.config_loader import ConfigurationLoader


class TestConfigurationLoader:
    """Test cases for ConfigurationLoader class."""
    
    def test_load_empty_config(self):
        """Test loading with no configuration file."""
        loader = ConfigurationLoader()
        config = loader.get_configuration()
        assert config == {}
    
    def test_load_valid_yaml_config(self):
        """Test loading a valid YAML configuration."""
        config_data = {
            'version': '1.0',
            'model': {
                'id': 'test-model/test-id'
            },
            'instances': {
                'workers': {
                    'type': 'g6e.xlarge'
                }
            }
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(config_data, f)
            temp_path = f.name
        
        try:
            loader = ConfigurationLoader(temp_path)
            config = loader.get_configuration()
            assert config['model']['id'] == 'test-model/test-id'
            assert config['instances']['workers']['type'] == 'g6e.xlarge'
        finally:
            Path(temp_path).unlink()
    
    def test_merge_configurations(self):
        """Test merging file configuration with context parameters."""
        loader = ConfigurationLoader()
        
        file_config = {
            'model': {'id': 'file-model'},
            'instances': {
                'workers': {'type': 'g6e.xlarge'}
            },
            'sglang': {
                'quantization': 'awq'
            }
        }
        
        context_params = {
            'model_id': 'context-model',
            'instance_type': 'g6e.2xlarge',
            'kv_cache_dtype': 'fp8_e5m2'
        }
        
        merged = loader.merge_configurations(file_config, context_params)
        
        # Context parameters should override file config
        assert merged['model']['id'] == 'context-model'
        assert merged['instances']['workers']['type'] == 'g6e.2xlarge'
        # File config should be preserved if not overridden
        assert merged['sglang']['quantization'] == 'awq'
        # New context parameters should be added
        assert merged['sglang']['kv_cache_dtype'] == 'fp8_e5m2'
    
    def test_to_context_params(self):
        """Test converting configuration to context parameters."""
        loader = ConfigurationLoader()
        
        config = {
            'model': {
                'id': 'test-model',
                'revision': 'main'
            },
            'instances': {
                'workers': {
                    'type': 'g6e.xlarge'
                },
                'router': {
                    'ip': '10.0.0.100'
                }
            },
            'sglang': {
                'quantization': 'awq_marlin',
                'mem_fraction_static': 0.85
            }
        }
        
        params = loader.to_context_params(config)
        
        assert params['model_id'] == 'test-model'
        assert params['revision'] == 'main'
        assert params['instance_type'] == 'g6e.xlarge'
        assert params['router_ip'] == '10.0.0.100'
        assert params['quantization'] == 'awq_marlin'
        assert params['mem_fraction_static'] == 0.85
    
    def test_validate_config_missing_required(self):
        """Test validation with missing required fields."""
        loader = ConfigurationLoader()
        
        # Missing version
        with pytest.raises(ValueError, match="Required field 'version' missing"):
            loader.validate_config({'model': {'id': 'test'}})
        
        # Missing model
        with pytest.raises(ValueError, match="Required field 'model' missing"):
            loader.validate_config({'version': '1.0'})
        
        # Missing model id
        with pytest.raises(ValueError, match="Model ID is required"):
            loader.validate_config({
                'version': '1.0',
                'model': {},
                'instances': {'workers': {'type': 'g6e.xlarge'}}
            })
    
    def test_validate_config_invalid_version(self):
        """Test validation with invalid version."""
        loader = ConfigurationLoader()
        
        with pytest.raises(ValueError, match="Unsupported configuration version"):
            loader.validate_config({
                'version': '2.0',
                'model': {'id': 'test'},
                'instances': {'workers': {'type': 'g6e.xlarge'}}
            })
    
    def test_get_default_config(self):
        """Test getting default configuration."""
        default = ConfigurationLoader.get_default_config()
        
        assert default['version'] == '1.0'
        assert default['model']['id'] == 'Valdemardi/DeepSeek-R1-Distill-Qwen-32B-AWQ'
        assert default['instances']['workers']['type'] == 'g6e.xlarge'
        assert default['instances']['router']['ip'] == '10.0.0.100'
    
    def test_file_not_found(self):
        """Test handling of non-existent configuration file."""
        loader = ConfigurationLoader('non-existent-file.yaml')
        
        with pytest.raises(FileNotFoundError):
            loader.get_configuration()


if __name__ == '__main__':
    pytest.main([__file__, '-v'])