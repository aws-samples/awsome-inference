"""Integration tests for SGLang cluster deployment.

These tests verify that the SGLang cluster is functioning correctly by:
1. Discovering the router instance
2. Testing connectivity
3. Sending OpenAI API requests
4. Validating responses
"""

import os
import sys
import time
import pytest
import requests
import boto3
from typing import Optional, Dict, Any
from openai import OpenAI


class TestSGLangCluster:
    """Integration tests for SGLang cluster functionality."""
    
    @classmethod
    def setup_class(cls):
        """Set up test fixtures for the entire test class."""
        cls.router_ip = cls._discover_router_ip()
        cls.base_url = f"http://{cls.router_ip}:8000"
        cls.client = OpenAI(
            base_url=f"{cls.base_url}/v1",
            api_key="None"  # SGLang doesn't require API key
        )
        cls.model_name = os.environ.get("SGLANG_MODEL_NAME", "meta-llama/Meta-Llama-3.1-8B-Instruct")
        
    @classmethod
    def _discover_router_ip(cls) -> str:
        """Discover the router instance IP address.
        
        First checks environment variable, then queries AWS for the router instance.
        """
        # Check if router IP is provided via environment variable
        if router_ip := os.environ.get("SGLANG_ROUTER_IP"):
            return router_ip
            
        # Otherwise, discover via AWS API
        ec2 = boto3.client('ec2')
        
        try:
            # Look for instance with private IP 10.0.0.100 (router's fixed IP)
            response = ec2.describe_instances(
                Filters=[
                    {'Name': 'private-ip-address', 'Values': ['10.0.0.100']},
                    {'Name': 'instance-state-name', 'Values': ['running']}
                ]
            )
            
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    if public_ip := instance.get('PublicIpAddress'):
                        return public_ip
                        
            raise RuntimeError("Could not find running router instance with IP 10.0.0.100")
            
        except Exception as e:
            raise RuntimeError(f"Failed to discover router IP: {e}")
    
    def test_router_connectivity(self):
        """Test basic connectivity to the router."""
        response = requests.get(f"{self.base_url}/health", timeout=10)
        assert response.status_code == 200, f"Router health check failed: {response.status_code}"
        
    def test_openai_models_endpoint(self):
        """Test the OpenAI models endpoint."""
        response = requests.get(f"{self.base_url}/v1/models", timeout=10)
        assert response.status_code == 200
        
        data = response.json()
        assert "data" in data
        assert len(data["data"]) > 0
        
        # Verify model structure
        model = data["data"][0]
        assert "id" in model
        assert "object" in model
        assert model["object"] == "model"
        
    def test_chat_completion_basic(self):
        """Test basic chat completion functionality."""
        response = self.client.chat.completions.create(
            model=self.model_name,
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "Say 'Hello, SGLang cluster is working!' exactly."}
            ],
            temperature=0,
            max_tokens=50
        )
        
        # Validate response structure
        assert response.id is not None
        assert response.object == "chat.completion"
        assert len(response.choices) > 0
        
        # Validate choice structure
        choice = response.choices[0]
        assert choice.index == 0
        assert choice.message.role == "assistant"
        assert choice.message.content is not None
        assert len(choice.message.content) > 0
        
        # Validate usage information
        assert response.usage is not None
        assert response.usage.prompt_tokens > 0
        assert response.usage.completion_tokens > 0
        assert response.usage.total_tokens == response.usage.prompt_tokens + response.usage.completion_tokens
        
    def test_chat_completion_streaming(self):
        """Test streaming chat completion."""
        stream = self.client.chat.completions.create(
            model=self.model_name,
            messages=[
                {"role": "user", "content": "Count from 1 to 5"}
            ],
            stream=True,
            max_tokens=50
        )
        
        chunks = []
        for chunk in stream:
            chunks.append(chunk)
            
        # Validate we received multiple chunks
        assert len(chunks) > 1
        
        # Validate chunk structure
        first_chunk = chunks[0]
        assert first_chunk.object == "chat.completion.chunk"
        assert len(first_chunk.choices) > 0
        
        # Reconstruct full response
        full_response = ""
        for chunk in chunks:
            if chunk.choices[0].delta.content:
                full_response += chunk.choices[0].delta.content
                
        assert len(full_response) > 0
        
    def test_error_handling_empty_messages(self):
        """Test error handling for empty messages."""
        with pytest.raises(Exception) as exc_info:
            self.client.chat.completions.create(
                model=self.model_name,
                messages=[],
                max_tokens=10
            )
            
        assert exc_info.value is not None
        
    def test_context_length_handling(self):
        """Test handling of different context lengths."""
        # Test with short context
        short_response = self.client.chat.completions.create(
            model=self.model_name,
            messages=[
                {"role": "user", "content": "Hi"}
            ],
            max_tokens=10
        )
        assert short_response.usage.prompt_tokens < 50
        
        # Test with longer context
        long_text = "This is a test. " * 100  # ~400 tokens
        long_response = self.client.chat.completions.create(
            model=self.model_name,
            messages=[
                {"role": "user", "content": long_text}
            ],
            max_tokens=10
        )
        assert long_response.usage.prompt_tokens > 200
        
    @pytest.mark.timeout(120)
    def test_worker_autoscaling(self):
        """Test that workers are properly registered with the router.
        
        This test verifies the router can see worker instances.
        """
        # Query router's worker status endpoint (if available)
        # Note: This assumes the router exposes a workers endpoint
        try:
            response = requests.get(f"{self.base_url}/workers", timeout=10)
            if response.status_code == 200:
                data = response.json()
                assert "workers" in data or "instances" in data
                # Verify at least one worker is registered
                workers = data.get("workers", data.get("instances", []))
                assert len(workers) > 0, "No workers registered with router"
        except requests.exceptions.ConnectionError:
            # If endpoint doesn't exist, skip this test
            pytest.skip("Workers endpoint not available")


if __name__ == "__main__":
    # Allow running directly with python
    pytest.main([__file__, "-v"])