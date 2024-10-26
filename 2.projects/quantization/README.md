# Quantization

Models keep getting bigger. To keep cost of inference low, we need novel ways to compress models.

<center><img src="model_size.png" width="80%"/> </br>
</center>


Ways to compress models:

1. Pruning: Remove layers in a model that do not improve the model. For example, remove layers that have weights close to zero. Pruned models can have accuracy concerns.
2. Knowledge Distillation: Train a smaller student model to emulate the larger teacher model. Can be computationally challenging for large models.
3. Quantization: Compress a model with weight is fp32 precision to lower precision such as int8 without losing accuracy.

Next we will deep dive into Quantization theory and different ways to quantize models.

## Data Types

1. FP32: Uses 4 bytes to store a parameter
2. INT8: Uses 1 byte to store a parameter
3. BF16 has a bigger range than FP16 but is less precise
4. Use `torch.iinfo(torch.int8)` or `torch.finfo(torch.float32)` to see more details

```
# Python by default saves in FP64
>>> number = 1/3
>>> number
0.3333333333333333
>>> format(number,'0.60f')
'0.333333333333333314829616256247390992939472198486328125000000'
>>> tensor_fp32 = torch.tensor(number,dtype=torch.float32)
>>> format(tensor_fp32, '0.60f')
'0.333333343267440795898437500000000000000000000000000000000000'
>>> tensor_fp16 = torch.tensor(number,dtype=torch.float16)
>>> format(tensor_fp16, '0.60f')
'0.333251953125000000000000000000000000000000000000000000000000'
>>> tensor_bf16 = torch.tensor(number,dtype=torch.bfloat16)
>>> format(tensor_bf16, '0.60f')
'0.333984375000000000000000000000000000000000000000000000000000'
>>> tensor_int8 = torch.tensor(number,dtype=torch.int8)
<stdin>:1: DeprecationWarning: an integer is required (got type float).  Implicit conversion to integers using __int__ is deprecated, and may be removed in a future version of Python.
>>> format(tensor_int8, '0.60f')
'0.000000000000000000000000000000000000000000000000000000000000'
>>>
```


## How to quantize models post-training to accelerate inference?

## What is quantization?


## Quantization basics?


## Quantization methods?


## Evaluating quantization methods


## Resources

1. [A Visual Guide to Quantization](https://newsletter.maartengrootendorst.com/p/a-visual-guide-to-quantization) 
2. [Quantization Fundamentals with Hugging Face](https://learn.deeplearning.ai/courses/quantization-fundamentals/lesson/1/introduction)
3. [Quantization in Depth](https://www.deeplearning.ai/short-courses/quantization-in-depth/)
4. [How Fireworks evaluates quantization precisely and interpretably](https://fireworks.ai/blog/fireworks-quantization)
