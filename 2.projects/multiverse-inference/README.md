# Get Started with Mutliverse Compactif AI

[multiverse](https://multiversecomputing.com/)

[compactifAI](https://multiversecomputing.com/compactifai)

These scripts provide an easy way to get started with Mutliverse CompactifAI training and inference from its REST API. It is designed to be as simple as possible, requires no data preparation, and uses a simple linux terminal environment.

mc stands for Multiverse Computing/CompactifAI

it's based on the paper [CompactifAI: Extreme Compression of Large Language Models using Quantum-Inspired Tensor Networks](https://arxiv.org/abs/2401.14109)
Other papers are [available](https://multiversecomputing.com/papers)

## 0. Documentations

from https://compactifai.singularity-quantum.com/docs

### Authentication
* GET /session/status # Returns the authentication status.
### Models
* GET /models/original # Returns the list of original models.
* GET /models/compressed # Returns the list of compressed models.
* GET /models/original/{model_id}/info # Returns information about an original model.
* GET /models/compressed/{model_id}/info # Returns information about a compressed model.
* GET /models/original/{model_id}/content # Returns a download link for the provided original model.
* GET /models/compressed/{model_id}/content # Returns a download link for the provided compressed model.
* POST /models/compressed/{model_id}/heal # Creates a healing request for a compressed model.
* POST /models/original/{model_id}/profile # Creates a profiling request.
* POST /models/original/{model_id}/compress # Creates a compression request.
### Jobs
* GET /jobs/{job_id}/status # Returns the status of the job.
* GET /jobs/{job_id}/result # Returns the result of the job.

## 1. Create Environment

a 
1. b
* c
2. c

```
python3 -m venv venv && source venv/bin/activate
python3 -m pip install torch torchvision transformers datasets typing tqdm
python3 -m joinem # parquet merging for OSCAR-2301-Hindi-Cleaned-3.0.parquet
```

