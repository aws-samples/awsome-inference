# CDK Infrastructure Components

This directory contains all AWS CDK infrastructure code for deploying SGLang on AWS.

## Files Overview

### Core Stack
- **[cdk_stack.py](./cdk_stack.py)** - Main CDK stack that orchestrates all components. Entry point for the infrastructure deployment.

### Infrastructure Components

- **[vpc.py](./vpc.py)** - Creates the Virtual Private Cloud (VPC) with public and private subnets for network isolation.

- **[image_builder.py](./image_builder.py)** - EC2 Image Builder pipeline that creates custom AMIs with pre-downloaded models for fast worker startup.

- **[router.py](./router.py)** - Deploys the load balancer EC2 instance that distributes requests across workers. Runs the [router script](../src/run_router.py).

- **[workers.py](./workers.py)** - Auto Scaling Group of GPU instances that run SGLang inference servers. Executes the [worker script](../src/run_worker.py).

- **[logs.py](./logs.py)** - CloudWatch configuration for centralized logging and monitoring.

- **[connections.py](./connections.py)** - Security group rules and network connections between components.

### Configuration Management

- **[config_loader.py](./config_loader.py)** - Configuration loader that handles YAML config files and CDK context parameters. Provides:
  - YAML configuration file loading from [../configs/](../configs/)
  - Schema validation against [JSON schema](../configs/schema/sglang-config-v1.0.json)
  - Merging of file configs with CLI context parameters (CLI takes precedence)
  - Default configuration with `openai/gpt-oss-20b` model
  - Backward compatibility with existing CDK context parameters

## Architecture Flow

1. **VPC** provides network isolation
2. **Image Builder** creates AMIs with models pre-installed
3. **Router** instance accepts client requests on port 8000
4. **Workers** register with router and handle inference
5. **Logs** collect metrics and logs from all components
6. **Connections** ensure secure communication

## Key Features

- **Pre-built AMIs** - Models downloaded during AMI creation for 5-10x faster scaling
- **Auto-scaling** - Workers scale based on request load with warm pools
- **Health checks** - Automatic detection and replacement of unhealthy instances
- **Service discovery** - Router automatically discovers workers via AWS APIs

## Related Files

- Configuration: [../app.py](../app.py), [../cdk.json](../cdk.json)
- Runtime scripts: [../src/](../src/)
- Tests: [../tests/unit/test_cdk_stack.py](../tests/unit/test_cdk_stack.py)
- Documentation: [../CLAUDE.md](../CLAUDE.md)