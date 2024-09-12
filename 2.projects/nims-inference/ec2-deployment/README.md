# NIM EC2 Deployment

This demo will show you how to deploy an [NVIDIA NIM](https://www.nvidia.com/en-us/ai/) to an Amazon EC2 instance and enable it for inference.

## Requirements

- NGC API key
- Route 53 Hosted Zone/Domain
- On-Demand vCPU quota

### NGC API Key

In order to use this demo, you will need an NGC API key. This key can be generated here: https://org.ngc.nvidia.com/setup/personal-keys

We will upload this key to [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) and will be used within the EC2 instance to log in to NGC to download the container.

### Route 53 Hosted Zone/Domain

To enable [TLS security on the Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html), we need to generate a certificate using [AWS Certificate Manager](https://aws.amazon.com/certificate-manager/). In order to generate this certificate, we need a domain and Hosted Zone in [Amazon Route 53](https://aws.amazon.com/route53/). We will configure this before launching the stack.

### On-Demand vCPU quota

This demo will launch a G5 EC2 instance. The number of vCPUs used by this instance will depend on the size. For example, a G5.12xlarge instance will use 48 vCPUs. Be sure to [check your utilization and quota value](https://us-west-2.console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-DB2E81BA) to make sure you can launch this instance. You can request an increase if necessary.

## Setup

### .env Configuration

Before launching, be sure to configure a `.env` file. Many of these fields can be left with their defaults.

```
# Stack Configuration
STACK_NAME=nim-stack
AWS_REGION=us-west-2
TEMPLATE_FILE=nims-stack.yaml

# Instance Configuration
INSTANCE_TYPE=g5.12xlarge

# AWS Resources
KEY_NAME=REPLACE_WITH_YOUR_KEY
VPC_ID=
SUBNET_IDS=

# Domain Configuration
DOMAIN_NAME=HOSTNAME.EXAMPLE.COM
HOSTED_ZONE_ID=REPLACE_WITH_YOUR_HOSTED_ZONE_ID

# NVIDIA Configuration
NGC_API_KEY_SECRET_NAME=NGCApiKeySecret
NGC_API_KEY=REPLACE_WITH_YOUR_NGC_API_KEY
REPOSITORY=nim/meta/llama3-8b-instruct
LATEST_TAG=1.0.0
```

You will need to update the following before launching:

```
# AWS Resources
KEY_NAME=REPLACE_WITH_YOUR_KEY

# Domain Configuration
DOMAIN_NAME=HOSTNAME.EXAMPLE.COM
HOSTED_ZONE_ID=REPLACE_WITH_YOUR_HOSTED_ZONE_ID

# NVIDIA Configuration
NGC_API_KEY=REPLACE_WITH_YOUR_NGC_API_KEY
```

### Secret Update

To upload the NGC API key to Secrets Manager, run the script:

```
./update_ngc_api_key.sh
```

This API Key will be retrieved by the EC2 instance during deployment.

### Launch Cloudformation Stack

You can either create the stack in the AWS Console, or through the included script. The script will populate the parameters required that were configured in the `.env` file. You will need to configure the required parameters in the console.

## Inference

Once the deployment succeeds, you can run inference requests against it using a variety of tools. Included is a script that uses `curl` to make a request to the endpoint using the configured domain name.

```
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
```

To test the endpoint and inference:

```
./inference.sh
```

# How it Works

## Components

![Overview](/images/Overview.png)

### EC2 Instance

- Uses a G5 instance type (default: g5.12xlarge) for GPU capabilities
- Runs Ubuntu with NVIDIA drivers, Docker, and NVIDIA Container Toolkit
- Automatically pulls and runs the specified NIM container

### Auto Scaling Group (ASG)

- Manages a single EC2 instance
- Ensures high availability and easy updates
- Uses a Launch Template for instance configuration

### Application Load Balancer (ALB)

- Provides HTTPS termination
- Routes traffic to the EC2 instance
- Uses an ACM certificate for HTTPS

### VPC and Networking

- Creates a new VPC with public subnets (or uses existing ones)
- Sets up necessary security groups and routing

### Route 53

- Creates a DNS record pointing to the ALB

## EC2 Configuration

1. The stack creates or uses existing VPC and subnets
2. An EC2 instance is launched with the necessary software and configurations
3. The NIM container is pulled and started on the EC2 instance
4. An ALB is set up to route traffic to the EC2 instance
5. A Route 53 record is created to point the specified domain to the ALB

The stack uses conditions to determine whether to create new VPC resources or use existing ones, making it flexible for different deployment scenarios.

## UserData Script Details

The UserData script in the Launch Template performs several key setup tasks:

1. **System Updates and Dependencies**

   - Updates the package list
   - Installs Python3-pip, AWS CLI, and CloudFormation helper scripts

2. **NVIDIA Driver and CUDA Installation**

   - Installs Linux headers
   - Adds NVIDIA CUDA repository
   - Installs CUDA drivers

3. **Docker Installation**

   - Adds Docker repository
   - Installs Docker CE

4. **NVIDIA Container Toolkit Installation**

   - Adds NVIDIA Docker repository
   - Installs nvidia-docker2
   - Restarts Docker service

5. **NGC API Key Retrieval**

   - Fetches the NGC API Key from AWS Secrets Manager

6. **NIM Container Setup and Run**

   - Sets up environment variables for the container
   - Creates a local cache directory
   - Logs in to the NGC container registry
   - Runs the NIM container with the following configuration:
     - Uses NVIDIA runtime
     - Exposes port 8000
     - Mounts a local cache volume
     - Sets the NGC API Key as an environment variable

7. **Signaling**
   - Signals the success or failure of the setup to CloudFormation

## Docker Container and ALB Interaction

1. **Container Exposure**

   - The NIM container exposes port 8000 inside the EC2 instance

2. **Security Group Configuration**

   - The EC2 security group allows inbound traffic on port 8000 from the ALB security group

3. **ALB Target Group**

   - An ALB Target Group is created with the following properties:
     - Protocol: HTTP
     - Port: 8000
     - Health check path: /health

4. **ALB Listener**

   - The ALB listener is configured for HTTPS (port 443)
   - It forwards traffic to the Target Group

5. **Request Flow**

   - Incoming HTTPS requests hit the ALB
   - The ALB terminates SSL and forwards the request as HTTP to the EC2 instance on port 8000
   - The Docker container receives the request on port 8000 and processes it

6. **Health Checks**
   - The ALB periodically sends health check requests to the `/health` endpoint
   - The NIM container responds to these health checks, allowing the ALB to determine if the instance is healthy
