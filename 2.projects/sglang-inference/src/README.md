# Runtime Scripts

This directory contains the runtime scripts that execute on the deployed EC2 instances.

## Files Overview

### Core Services

- **[run_router.py](./run_router.py)** - Router service that runs on the load balancer instance
  - Discovers worker instances via AWS Auto Scaling APIs
  - Launches and manages the SGLang router process
  - Handles worker registration/deregistration
  - Restarts automatically if the process exits
  - Deployed by: [../cdk/router.py](../cdk/router.py)

- **[run_worker.py](./run_worker.py)** - Worker service that runs on GPU instances
  - Launches SGLang inference server with specified model
  - Registers with router on startup
  - Handles graceful shutdown
  - Supports all SGLang CLI parameters
  - Deployed by: [../cdk/workers.py](../cdk/workers.py)

### Monitoring

- **[monitor_logs.py](./monitor_logs.py)** - CloudWatch metrics collector
  - Monitors SGLang log files for performance metrics
  - Publishes custom CloudWatch metrics (tokens, latency, etc.)
  - Runs as a background process on worker instances
  - Used by: [../cdk/workers.py](../cdk/workers.py)

### Configuration

- **[config.json](./config.json)** - CloudWatch agent configuration
  - Defines log groups and streams
  - Specifies which files to monitor
  - Configures metric namespaces
  - Referenced by: [../cdk/logs.py](../cdk/logs.py)

## Execution Flow

1. **Router Instance**:
   - Runs `run_router.py` on startup
   - Discovers workers in Auto Scaling Group
   - Starts SGLang router on port 8000

2. **Worker Instances**:
   - Run `run_worker.py` on startup
   - Start SGLang server on port 7999
   - Register with router for load balancing
   - Run `monitor_logs.py` for metrics

## Environment Variables

Scripts use these environment variables:
- `AWS_REGION` - AWS region (auto-detected if not set)
- `SGLANG_ROUTER_URL` - Router endpoint for workers

## Related Files

- Infrastructure: [../cdk/](../cdk/)
- Tests: [../tests/](../tests/)
- Documentation: [../CLAUDE.md](../CLAUDE.md), [../Install.md](../Install.md)