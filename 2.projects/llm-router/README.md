# LLM Routers

An LLM (Large Language Model) router is a system designed to dynamically direct queries to the most appropriate language model based on the complexity and requirements of the task. The router is trained on a dataset that includes examples of queries and their corresponding performance outcomes when handled by different models. This training enables the router to learn patterns and characteristics of queries that are likely to be handled effectively by weaker or stronger models.

Benefits of LLM Routers include:

1. **Cost Optimization**: By routing simpler queries to weaker, more cost-effective models and reserving complex tasks for more powerful models, LLM routers can significantly reduce costs without compromising on quality. This approach optimizes resource allocation, ensuring that computationally expensive models are used only when necessary.

2. **Performance and Latency**: LLM routers can improve response times by using smaller, faster models for simpler tasks. This granular approach allows developers to build highly efficient and responsive AI systems that maintain high performance across diverse use cases

## Pre-requisites

## Create conda env

```
#!/bin/bash

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

source ./miniconda3/bin/activate

conda create -n llm-router  python=3.11

source activate llm-router

conda install -y pytorch=2.4.1 torchvision torchaudio transformers datasets fsspec=2023.9.2 pytorch-cuda=12.1 "numpy=1.*" -c pytorch -c nvidia

pip install boto3
pip install "routellm[serve,eval]"
```
