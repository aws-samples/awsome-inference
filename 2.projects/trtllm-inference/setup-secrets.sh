#!/bin/bash

# Check if 3.local_inference.sh exists
if [ -f "3.local_inference.sh" ]; then
    # Get the existing Hugging Face Access Token and Username from 3.local_inference.sh
    HF_TOKEN=$(grep -o -E 'HF_TOKEN="[^"]*"' 3.\ Within\ Container/3.local_inference.sh | cut -d'=' -f2 | tr -d '"')
    HF_USERNAME=$(grep -o -E 'HF_USERNAME="[^"]*"' 3.\ Within\ Container/3.local_inference.sh | cut -d'=' -f2 | tr -d '"')
else
    HF_TOKEN=""
    HF_USERNAME=""
fi

# Prompt user for Hugging Face Username
read -p "Enter your Hugging Face Username: " new_HF_USERNAME

# Use the new username if provided, otherwise use the existing one
if [ -n "$new_HF_USERNAME" ]; then
    HF_USERNAME="$new_HF_USERNAME"
fi

# Prompt user for Hugging Face Access Token
read -p "Enter your Hugging Face Access Token: " new_HF_TOKEN

# Use the new token if provided, otherwise use the existing one
if [ -n "$new_HF_TOKEN" ]; then
    HF_TOKEN="$new_HF_TOKEN"
fi

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Prompt user for Capacity Reservation ID
read -p "Enter your Capacity Reservation ID: " CR_ID

# Prompt user for Docker registry name
read -p "Enter your Docker registry name (enter trtllm-inference-registry if you want to use default): " DOCKER_REGISTRY_NAME

# Prompt user for image tag
read -p "Enter the image tag for the image you'd like to use (enter latest if you want to use default): " IMAGE_TAG

# Update cluster-config.yaml
sed -i "s/cr-0ce6be6d411d2f43f/$CR_ID/" 1.\ Setup\ Cluster/cluster-config.yaml

# Update 3.local_inference.sh
sed -i "s/HF_USERNAME=\"[^\"]*\"/HF_USERNAME=\"$HF_USERNAME\"/" 3.\ Within\ Container/3.local_inference.sh
sed -i "s/HF_TOKEN=\"[^\"]*\"/HF_TOKEN=\"$HF_TOKEN\"/" 3.\ Within\ Container/3.local_inference.sh

# Update manifest.yaml
sed -i "s/123456789012/$AWS_ACCOUNT_ID/" 2.\ Setup\ Container/manifest.yaml
sed -i "s/trtllm-inference-registry/$DOCKER_REGISTRY_NAME/" 2.\ Setup\ Container/manifest.yaml
sed -i "s/latest/$IMAGE_TAG/" 2.\ Setup\ Container/manifest.yaml

# Update ecr-secret.sh
sed -i "s/123456789012/$AWS_ACCOUNT_ID/" 2.\ Setup\ Container/ecr-secret.sh

echo "Updated the following files:"
echo "- 1.cluster-config.yaml with your Capacity Reservation ID"
echo "- 2. Setup Container/manifest.yaml with your AWS Account ID, Docker registry name, and image tag"
echo "- 2. Setup Container/ecr-secret.sh with your AWS Account ID"
echo "- 3.local_inference.sh with your Hugging Face Username and Access Token"
