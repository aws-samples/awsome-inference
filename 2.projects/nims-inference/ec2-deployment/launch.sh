#!/bin/bash

# Enable exit on error and debug output
set -e

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to log errors
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >&2
}

log_message "Script started"

# Load environment variables from .env file
if [ -f .env ]; then
    log_message "Loading .env file..."
    set -a
    source .env
    set +a
    log_message ".env file loaded"
else
    log_error ".env file not found"
    exit 1
fi

# Check required variables
required_vars=(
    "STACK_NAME"
    "AWS_REGION"
    "TEMPLATE_FILE"
    "INSTANCE_TYPE"
    "KEY_NAME"
    "DOMAIN_NAME"
    "HOSTED_ZONE_ID"
    "REPOSITORY"
    "LATEST_TAG"
    "NGC_API_KEY_SECRET_NAME"
)

log_message "Checking required variables..."
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        log_error "$var is not set in the .env file"
        exit 1
    fi
    log_message "$var is set"
done

# Set optional variables with default values
VPC_ID=${VPC_ID:-""}
SUBNET_IDS=${SUBNET_IDS:-""}

# Function to create the CloudFormation stack
create_stack() {
    log_message "Attempting to create CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --disable-rollback \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters \
            ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
            ParameterKey=KeyName,ParameterValue="$KEY_NAME" \
            ParameterKey=DomainName,ParameterValue="$DOMAIN_NAME" \
            ParameterKey=HostedZoneId,ParameterValue="$HOSTED_ZONE_ID" \
            ParameterKey=VpcId,ParameterValue="$VPC_ID" \
            ParameterKey=SubnetIds,ParameterValue="$SUBNET_IDS" \
            ParameterKey=Repository,ParameterValue="$REPOSITORY" \
            ParameterKey=LatestTag,ParameterValue="$LATEST_TAG" \
            ParameterKey=NGCApiKeySecretName,ParameterValue="$NGC_API_KEY_SECRET_NAME" \
        --capabilities CAPABILITY_IAM \
        --no-cli-pager
    
    if [ $? -eq 0 ]; then
        log_message "Stack creation initiated successfully"
    else
        log_error "Failed to create stack"
        exit 1
    fi
}

# Call the function to create the stack
log_message "Calling create_stack function..."
create_stack

log_message "Waiting for stack creation to complete..."
if aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" --no-cli-pager; then
    log_message "Stack creation completed successfully"
else
    log_error "Stack creation failed or timed out"
    exit 1
fi

log_message "Script completed successfully"