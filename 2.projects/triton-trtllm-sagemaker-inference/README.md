# Triton TensorRT-LLM on Amazon SageMaker Examples

## Examples

1. For Deploying Encoder-Decoder Model like T5/BART with Triton TensorRT-LLM see jupyter notebook [enc_dec_sagemaker.ipynb](./enc_dec_sagemaker.ipynb)

## AWS Sagemaker Notebook Configuration

- Login to AWS and navigate to the **Amazon Sagemaker** service

- Configure a SageMaker notebook using instance type `g5.xlarge`
<br />
<img src="img/sm_01.png" alt="Configure a new notebook" width="550"/>

- Configure the instance with enough storage to accommodate container image pull(s) and model weights - `100GB` should be adequate
<br />
<img src="img/sm_02.png" alt="Set notebook instance parameters" width="550"/>

- Ensure IAM role `AmazonSageMakerServiceCatalogProductsUseRole` is associated with your notebook
  - Note you may need to associate additional permissions with this role to permit ECR `CreateRepository` and image push operations
- Configure the Default repository and reference this repo: https://github.com/aws-samples/awsome-inference.git
- Click **Create notebook instance**
<br />
<img src="img/sm_03.png" alt="Set notebook permissions and git repo" width="550"/>

- Within the notebook instance navigate to [2.projects](https://github.com/aws-samples/awsome-inference/tree/main/2.projects)
