# Tests

This directory contains test scripts for validating the SGLang deployment and measuring performance.

## Files Overview

### Integration Tests

- **[test_oai.py](./test_oai.py)** - OpenAI API compatibility test
  - Tests the deployed system using OpenAI Python client
  - Sends multiple requests with random text samples
  - Generates performance graphs (tokens, latency)
  - Validates API response format

- **[test_metric_latency.py](./test_metric_latency.py)** - CloudWatch metrics latency test
  - Measures time for requests to appear in CloudWatch
  - Validates metric collection pipeline
  - Tests custom metrics (NewTokens, RunningRequests, etc.)
  - Useful for monitoring system debugging

- **[stress_test.py](./stress_test.py)** - Load testing script
  - Configurable concurrent workers
  - Sends requests with varying prompt sizes
  - Measures throughput and latency
  - Can be used for auto-scaling validation

### Test Data

- **[sample_text.txt](./sample_text.txt)** - Sample text for testing
  - Used by test scripts as input data
  - Contains varied content for realistic testing
  - Small file size for quick loading

### Unit Tests

- **[unit/](./unit/)** - Unit tests for CDK components
  - See [unit test README](./unit/README.md) for details

## Running Tests

### Prerequisites

Set environment variables (or create `.env` file):
```bash
export SGLANG_ROUTER_URL=http://<router-ip>:8000
export AWS_REGION=us-west-2
export MODEL_NAME=meta-llama/Meta-Llama-3.1-8B-Instruct
```

### Running Individual Tests

```bash
# Test OpenAI compatibility
python tests/test_oai.py

# Test CloudWatch metrics
python tests/test_metric_latency.py

# Run stress test
python tests/stress_test.py
```

### Dependencies

Tests require these Python packages:
- `openai` - OpenAI client library
- `boto3` - AWS SDK for CloudWatch
- `pandas`, `matplotlib` - For data analysis and visualization
- `requests` - HTTP client

## Test Output

- **test_oai.py** - Creates `api_metrics.png` with performance graphs
- **test_metric_latency.py** - Prints latency measurements to console
- **stress_test.py** - Displays real-time throughput statistics

## Related Files

- Runtime scripts being tested: [../src/](../src/)
- Infrastructure deploying the system: [../cdk/](../cdk/)
- Configuration examples: [../.env.example](../.env.example)