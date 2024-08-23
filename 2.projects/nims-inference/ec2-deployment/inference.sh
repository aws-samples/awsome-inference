#!/bin/bash

# Load domain from .env file
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

# Check if DOMAIN is set
if [ -z "$DOMAIN_NAME" ]; then
    echo "Error: DOMAIN_NAME is not set in .env file"
    exit 1
fi

# Get available models
echo "Fetching available models:"
models=$(curl -s -X GET "https://$DOMAIN_NAME/v1/models")
echo "$models" | jq '.'

# Extract the first model ID
model_id=$(echo "$models" | jq -r '.data[0].id')

if [ -z "$model_id" ]; then
    echo "Error: No models found"
    exit 1
fi

echo -e "\nUsing model: $model_id"

# Test inference with chat completion
echo -e "\nTesting chat completion inference:"
curl -s -X POST "https://$DOMAIN_NAME/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$model_id"'",
        "messages": [
            {"role": "user", "content": "Hello! How are you?"},
            {"role": "assistant", "content": "Hi! I am quite well, how can I help you today?"},
            {"role": "user", "content": "Write a short limerick about the wonders of GPU computing."}
        ],
        "max_tokens": 100
    }' | jq '.choices[0].message.content'

# Test inference with completion
echo -e "\nTesting completion inference:"
curl -s -X POST "https://$DOMAIN_NAME/v1/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$model_id"'",
        "prompt": "Once upon a time",
        "max_tokens": 64
    }' | jq '.choices[0].text'