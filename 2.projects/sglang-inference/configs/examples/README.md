# Example Configurations

This directory contains example configuration files to help you get started with SGLang CDK deployment.

## Available Examples

- `basic-config.yaml` - A minimal configuration example showing the basic structure

## Usage

Copy an example configuration and modify it for your needs:

```bash
cp configs/examples/basic-config.yaml my-config.yaml
# Edit my-config.yaml with your parameters
cdk deploy --config-file my-config.yaml
```

## Configuration Tips

1. **Start Simple**: Begin with a basic configuration and add parameters as needed
2. **Instance Types**: Choose appropriate GPU instances based on your model size