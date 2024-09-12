#!/bin/bash

# Enable exit on error
set -e

# Function to log errors
log_error() {
    echo "ERROR: $1" >&2
}

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading .env file..."
    export $(grep -v '^#' .env | xargs)
else
    log_error ".env file not found"
    exit 1
fi

# Check if NGC_API_KEY is set
if [ -z "$NGC_API_KEY" ]; then
    log_error "NGC_API_KEY is not set in the .env file"
    exit 1
fi

# Set default value for NGC_API_KEY_SECRET_NAME
NGC_API_KEY_SECRET_NAME=${NGC_API_KEY_SECRET_NAME:-"NGCApiKeySecret"}

# Check if AWS_REGION is set in .env, otherwise use the instance's region
if [ -z "$AWS_REGION" ]; then
    echo "AWS_REGION not set in .env, attempting to retrieve from instance metadata..."
    AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    if [ -z "$AWS_REGION" ]; then
        log_error "Failed to retrieve AWS region from instance metadata"
        exit 1
    fi
fi

echo "Using NGC_API_KEY_SECRET_NAME: $NGC_API_KEY_SECRET_NAME"
echo "Using AWS_REGION: $AWS_REGION"

# Function to create or update the secret
create_or_update_secret() {
    if aws secretsmanager describe-secret --secret-id "$NGC_API_KEY_SECRET_NAME" --region "$AWS_REGION" &> /dev/null; then
        echo "Secret exists. Updating..."
        if OUTPUT=$(aws secretsmanager update-secret \
            --secret-id "$NGC_API_KEY_SECRET_NAME" \
            --secret-string "$NGC_API_KEY" \
            --region "$AWS_REGION" 2>&1); then
            echo "Secret updated successfully"
        else
            log_error "Failed to update secret. AWS CLI returned the following error:"
            echo "$OUTPUT"
            return 1
        fi
    else
        echo "Secret does not exist. Creating..."
        if OUTPUT=$(aws secretsmanager create-secret \
            --name "$NGC_API_KEY_SECRET_NAME" \
            --description "NGC API Key for NVIDIA containers" \
            --secret-string "$NGC_API_KEY" \
            --region "$AWS_REGION" 2>&1); then
            echo "Secret created successfully"
        else
            log_error "Failed to create secret. AWS CLI returned the following error:"
            echo "$OUTPUT"
            return 1
        fi
    fi
}

# Call the function to create or update the secret
create_or_update_secret