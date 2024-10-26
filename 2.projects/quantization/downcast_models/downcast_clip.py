import torch

from PIL import Image
import requests

from transformers import CLIPProcessor, CLIPModel

from copy import deepcopy

def print_param_dtype(model):
    for name, param in model.named_parameters():
        print(f"{name} is loaded in {param.dtype}")

# Set Default data type
desired_dtype = torch.float32
torch.set_default_dtype(desired_dtype)

model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14")
processor = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")

url = "http://images.cocodataset.org/val2017/000000039769.jpg"
image = Image.open(requests.get(url, stream=True).raw)

inputs = processor(text=["a photo of a cat", "a photo of a dog"], images=image, return_tensors="pt", padding=True)

outputs_fp32 = model(**inputs)
logits_per_image_fp32 = outputs_fp32.logits_per_image # this is the image-text similarity score
probs_fp32 = logits_per_image_fp32.softmax(dim=1) # we can take the softmax to get the label probabilities

print(f'FP32 Output probs: {probs_fp32}')

# Cast model to fp16
model_fp16 = deepcopy(model)
model_fp16 = model_fp16.to(torch.float16)

outputs_fp16 = model_fp16(**inputs)
logits_per_image_fp16 = outputs_fp16.logits_per_image # this is the image-text similarity score
probs_fp16 = logits_per_image_fp16.softmax(dim=1) # we can take the softmax to get the label probabilities

print(f'FP16 Output probs: {probs_fp16}')

mean_diff = torch.abs(logits_per_image_fp16 - logits_per_image_fp32).mean().item()
max_diff = torch.abs(logits_per_image_fp16 - logits_per_image_fp32).max().item()

print(f"FP16 Logits Mean diff: {mean_diff} | Max diff: {max_diff}")

# Cast model to fp16
model_bf16 = deepcopy(model)
model_bf16 = model_bf16.to(torch.bfloat16)

outputs_bf16 = model_bf16(**inputs)
logits_per_image_bf16 = outputs_bf16.logits_per_image # this is the image-text similarity score
probs_bf16 = logits_per_image_bf16.softmax(dim=1) # we can take the softmax to get the label probabilities

print(f'BF16 Output probs: {probs_fp16}')

mean_diff = torch.abs(logits_per_image_bf16 - logits_per_image_fp32).mean().item()
max_diff = torch.abs(logits_per_image_bf16 - logits_per_image_fp32).max().item()

print(f"BF16 Logits Mean diff: {mean_diff} | Max diff: {max_diff}")

fp32_mem_footprint = model.get_memory_footprint()
fp16_mem_footprint = model_fp16.get_memory_footprint()
bf16_mem_footprint = model_bf16.get_memory_footprint()


print("Footprint of the fp32 model in GBs: ",fp32_mem_footprint/1e+9)
print("Footprint of the fp16 model in GBs: ",fp16_mem_footprint/1e+9)
print("Footprint of the bf16 model in GBs: ",bf16_mem_footprint/1e+9)
