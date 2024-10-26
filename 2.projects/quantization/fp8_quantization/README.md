# FP8 Quantization

FP8 quantization offers several advantages over INT8 quantization:

1. **Higher Dynamic Range**: FP8 can represent a wider range of values, making it more robust to outliers.
2. **Better Accuracy**: FP8 generally preserves model accuracy better than INT8, especially for smaller models.
3. **Hardware Support**: FP8 leverages native support on modern GPUs, improving latency and throughput.
4. **Quantization of Activations**: FP8 can efficiently quantize both weights and activations, which is beneficial for overall model performance.

However, INT8 remains widely used due to its simplicity and broad hardware support, but it may require additional techniques to mitigate its limitations.