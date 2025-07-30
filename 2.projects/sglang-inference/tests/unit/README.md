# Unit Tests

This directory contains unit tests for the CDK infrastructure components.

## Files Overview

### CDK Stack Tests

- **[test_cdk_stack.py](./test_cdk_stack.py)** - Unit tests for CDK stack
  - Validates CloudFormation template synthesis
  - Tests resource creation and configuration
  - Ensures proper IAM permissions
  - Verifies security group rules

## Running Unit Tests

```bash
# Run all unit tests
pytest tests/unit/

# Run with verbose output
pytest -v tests/unit/test_cdk_stack.py

# Run specific test
pytest tests/unit/test_cdk_stack.py::test_stack_creation
```

## Test Coverage

The unit tests validate:

1. **Stack Creation**
   - VPC with correct CIDR blocks
   - Subnets in multiple AZs
   - Internet gateway and NAT gateways

2. **Compute Resources**
   - Router EC2 instance configuration
   - Worker Auto Scaling Group settings
   - Instance types and AMI selection

3. **Security**
   - Security group ingress/egress rules
   - IAM roles and policies
   - Network isolation

4. **Monitoring**
   - CloudWatch log groups
   - Custom metrics configuration

## Writing New Tests

Follow the pattern in `test_cdk_stack.py`:

```python
def test_new_feature():
    app = App()
    stack = CdkStack(app, "test-stack")
    template = Template.from_stack(stack)
    
    # Assert resources exist
    template.has_resource("AWS::EC2::Instance", {
        "Properties": {
            "InstanceType": "r7i.xlarge"
        }
    })
```

## Related Files

- CDK components being tested: [../../cdk/](../../cdk/)
- Main application entry: [../../app.py](../../app.py)
- Integration tests: [../](../)