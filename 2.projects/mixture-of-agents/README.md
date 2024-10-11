# Mixture of Agents (MoA)

## Architecture & Description

Recent advances in large language models (LLMs) have shown substantial capabilities, but harnessing the collective expertise of multiple LLMs is an open direction. [Mixture-of-Agents (MoA)](https://github.com/togethercomputer/MoA) approach to leverages the collective strengths of multiple LLMs through a layered architecture. Each layer comprises multiple LLMs, and each model uses outputs from the previous layer's agents as auxiliary information.

MoA categorize's LLMs into two key roles during the collaborative process: proposers that excel at generating diverse reference responses to provide additional context, and aggregators that are proficient at synthesizing multiple inputs into a single high-quality output. 

![Architecture](/2.projects/mixture-of-agents/architecture-advanced.png)

The image presented illustrates a three-layered Mixture of Annotators (MoA) architecture. The first two layers comprise proposers, while the final layer consists of an aggregator. The central concept we aim to investigate in this project is the potential of leveraging cheaper Large Language Models (LLMs) in conjunction with the MoA approach to achieve comparable results to those obtained from more expensive, better performing LLMs.

We are using the following aggregator prompt recommended in [Mixture-of-Agents (MoA)](https://github.com/togethercomputer/MoA). 

```
You have been provided with a set of responses from various open-source models to the latest user query. Your task is to synthesize these responses into a single, high-quality response. It is crucial to critically evaluate the information provided in these responses, recognizing that some of it may be biased or incorrect. Your response should not simply replicate the given answers but should offer a refined, accurate, and comprehensive reply to the instruction. Ensure your response is well-structured, coherent, and adheres to the highest standards of accuracy and reliability. Do not write in response that this was synthesised from previous responses.

Responses from models:

<Response_1>...</Response_1>
<Response_2>...</Response_2>
<Response_3>...</Response_3>
```


## Prerequisites

1. Create an Amazon SageMaker Notebook Instance, follow [instructions](https://docs.aws.amazon.com/sagemaker/latest/dg/gs-setup-working-env.html) here. 
2. Open terminal in Sagemaker Notebook Instance, and run the following commands:

```
cd SageMaker/
git clone https://github.com/aws-samples/awsome-inference.git
```

3. Navigate to [awesome-inference/2.projects/mixture-of-agents/mixture-of-agents.ipynb](/2.projects/mixture-of-agents/mixture-of-agents.ipynb) file.

## ⛏️ Built Using <a name = "built_using"></a>

- [Amazon Sagemaker Notebook](https://docs.aws.amazon.com/sagemaker/latest/dg/nbi.html) 
- [Amazon Bedrock](https://aws.amazon.com/bedrock/)
- [Mixture of Agents](https://github.com/togethercomputer/MoA)
- [AlpacaEval 2.0](https://github.com/tatsu-lab/alpaca_eval)