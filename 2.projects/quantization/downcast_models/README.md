# Downcast CLIP models and examine impact on accuracy

```
(quant) awsankur@p5-dy-gpu-2:~/quantization$ python3 downcast_clip.py
FP32 Output probs: tensor([[9.9925e-01, 7.5487e-04]], grad_fn=<SoftmaxBackward0>)

FP16 Output probs: tensor([[9.9902e-01, 7.6723e-04]], dtype=torch.float16,
       grad_fn=<SoftmaxBackward0>)

FP16 Logits Mean diff: 0.008167266845703125 | Max diff: 0.013462066650390625

BF16 Output probs: tensor([[9.9902e-01, 7.6723e-04]], dtype=torch.float16,
       grad_fn=<SoftmaxBackward0>)

BF16 Logits Mean diff: 0.1224822998046875 | Max diff: 0.15408706665039062

Footprint of the fp32 model in GBs:  1.710468724
Footprint of the fp16 model in GBs:  0.855235698
Footprint of the bf16 model in GBs:  0.855235698
```