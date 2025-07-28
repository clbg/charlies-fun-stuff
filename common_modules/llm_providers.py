import os
import requests
import json
import base64
import boto3
from abc import ABC, abstractmethod
from typing import Optional
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

class LLMProvider(ABC):
    """Abstract base class for LLM providers"""
    
    @abstractmethod
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion from the LLM provider"""
        pass

class OpenAIProvider(LLMProvider):
    """OpenAI API provider"""
    
    def __init__(self, api_key: Optional[str] = None, model: str = "gpt-4.1", endpoint: str = "https://api.openai.com/v1/chat/completions"):
        self.api_key: Optional[str] = api_key or os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set or api_key parameter not provided.")
        self.model = model
        self.endpoint = endpoint
    
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion using OpenAI API"""
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            "max_tokens": max_tokens
        }
        
        response = requests.post(self.endpoint, json=payload, headers=headers)
        if response.status_code == 200:
            response_data = response.json()
            return response_data['choices'][0]['message']['content'].strip()
        else:
            raise Exception(f"API error: Status code {response.status_code}")

class AnthropicProvider(LLMProvider):
    """Anthropic Claude API provider"""
    
    def __init__(self, api_key: Optional[str] = None, model: str = "claude-3-sonnet-20240229", endpoint: str = "https://api.anthropic.com/v1/messages"):
        self.api_key: Optional[str] = api_key or os.getenv("ANTHROPIC_API_KEY")
        if not self.api_key:
            raise ValueError("ANTHROPIC_API_KEY environment variable not set or api_key parameter not provided.")
        self.model = model
        self.endpoint = endpoint
    
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion using Anthropic API"""
        headers = {
            "x-api-key": self.api_key,
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01"
        }
        
        payload = {
            "model": self.model,
            "max_tokens": max_tokens,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        }
        
        response = requests.post(self.endpoint, json=payload, headers=headers)
        if response.status_code == 200:
            response_data = response.json()
            return response_data['content'][0]['text'].strip()
        else:
            raise Exception(f"API error: Status code {response.status_code}")

class BedrockProvider(LLMProvider):
    """AWS Bedrock API provider for Claude models using boto3 with API key"""
    
    def __init__(self, api_key: Optional[str] = None, model: str = "us.anthropic.claude-sonnet-4-20250514-v1:0", region: str = "us-west-2"):
        self.api_key = api_key or os.getenv("AWS_BEARER_TOKEN_BEDROCK")
        if not self.api_key:
            raise ValueError("AWS_BEARER_TOKEN_BEDROCK environment variable not set or api_key parameter not provided.")
        self.model = model
        self.region = region
        
        # Ensure model is a Claude model
        if not "anthropic.claude" in self.model:
            raise ValueError(f"BedrockProvider only supports Claude models. Provided model: {self.model}")
        
        # Set the API key as an environment variable for boto3
        os.environ['AWS_BEARER_TOKEN_BEDROCK'] = self.api_key
        
        # Create boto3 client for Bedrock
        self.bedrock_client = boto3.client(
            service_name='bedrock-runtime',
            region_name=self.region
        )
    
    def generate_completion(self, prompt: str, max_tokens: int = 800) -> str:
        """Generate completion using AWS Bedrock API with Claude models via boto3"""
        try:
            # For newer Claude models, use converse API
                # Prepare messages for converse API
                messages = [
                    {
                        "role": "user", 
                        "content": [{"text": prompt}]
                    }
                ]
                
                # Call the converse API
                response = self.bedrock_client.converse(
                    modelId=self.model,
                    messages=messages,
                )
                
                # Extract the completion text from converse response
                return response['output']['message']['content'][0]['text'].strip()
        except Exception as e:
            raise Exception(f"AWS Bedrock API error: {str(e)}")

def create_llm_provider(provider_type: str = "openai", **kwargs) -> LLMProvider:
    """Factory function to create LLM providers
    
    Args:
        provider_type: Type of provider ("openai", "anthropic", or "bedrock")
        **kwargs: Additional parameters for the provider (api_key, model, endpoint)
    
    Returns:
        LLMProvider instance
    """
    if provider_type.lower() == "openai":
        return OpenAIProvider(**kwargs)
    elif provider_type.lower() == "anthropic":
        return AnthropicProvider(**kwargs)
    elif provider_type.lower() == "bedrock":
        return BedrockProvider(**kwargs)
    else:
        raise ValueError(f"Unsupported provider type: {provider_type}")
