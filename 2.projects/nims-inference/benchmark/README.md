# NIM Test Inference Results

The test inference results are only used internally as a baseline to compare the relative performance between models, quantization, and number of GPUs. 


### Table of Summary

| NGC name              | Image tag | Datatype | Instance # / GPU # | Status |
| :---------------- | :------: | ----: | ----: | ----: |
| [llama-3-8-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama3-8b-instruct)            | 1.0.0   | fp16 | 1x g5 / 1x A10   | |
|                                                                                                                   | 1.1.1   | fp16 | 1x g5 / 1x A10   | |
|                                                                                                                   | 1.1.1   | fp8  | 1x p5 / 1x H100  | |
| [llama-3-70b-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama3-70b-instruct)         | 1.0.0   | fp8  | 1x p5 / 4x H100   | |
|                                                                                                                   | 1.1.1   | fp8  | 1x p5 / 8x H100   | |
| [llama-3.1-8-base](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama-3.1-8b-base)               | 1.1.1   | fp16| 1x p5 / 1x H100   | WIP  |
|                                                                                                                   | 1.1.1   | fp8   | 1x p5 / 1x H100   | NIM error with fp8 |
| [llama-3.1-8-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama-3.1-8b-instruct)       | 1.1.1   | fp16  | 1x p5 / 1x H100   | WIP  |
|                                                                                                                   | 1.1.1   | fp8   | 1x p5 / 1x H100   | NIM error with fp8 |
| [llama-3.1-70b-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama-3.1-70b-instruct)    | 1.1.1   | fp16 | 1x p5 / 4x H100   | |
|                                                                                                                   | 1.1.1   | fp8   | 1x p5 / 4x H100   | NIM error with fp8 |
| llama-3.1-405b-instruct                                                                                           | 1.1.1   | fp16 | 2x p5 / 8x H100   | Waiting for NV to release  |
|                                                                                                                   | 1.1.1   | fp8   | 1x p5 / 8x H100   |  |
| [Mixtral-8x22B-Instruct-v0.1](https://catalog.ngc.nvidia.com/orgs/nim/teams/mistralai/containers/mixtral-8x22b-instruct-v01) | 1.0.0   | fp16 | 1x p5 / 8x H100   |  |




### Testings results

| Model                                 | Dtype | GPUs   | Input/Output sequence length | Concurrency      | 1      | 2      | 4      | 8       | 16      | 32      | 64      | 128      | 512      | 1024     | 2048    |
| :------:                              | :---: | :----: | :-------:                    | :------:         | :---:  | :---:  | :----: | :----:  | :----:  | :----:  | :----:  | :----:   | :----:   | :----:   | :----:  |
| meta/llama3-8b-instruct               | fp16  | 1xA10  | 200/114                      | Token-per-second | 33.59  | 67.88  | 132.63 | 249.43  | 444.14  | 748.54  | 751.67  | 751.21   | 750.92   | 746.93   | 751.75  |
| meta/llama3-8b-instruct               | fp16  | 2xA10  | 200/114                      | Token-per-second | 61.3   | 114.71 | 214.81 | 366.1   | 603.76  | 922.2   | 924.95  | 927.09   | 926.53   | 925.3    | 924.51  |
| meta/llama3-8b-instruct               | fp8   | 1xH100 | 200/114                      | Token-per-second | 221.89 | 434.89 | 852.19 | 1634.56 | 2770.71 | 4948.9  | 7815.08 | 10215.99 | 10811.09 | 11956.25 | 11395.5 |

| Model                                 | Dtype | GPUs   | Input/Output sequence length | Concurrency      | 1      | 2      | 4      | 8       | 16      | 32      | 64      | 128      | 512      | 1024     | 2048    |
| :------:                              | :---: | :----: | :-------:                    | :------:         | :---:  | :---:  | :----: | :----:  | :----:  | :----:  | :----:  | :----:   | :----:   | :----:   | :----:  |
| meta/llama3-70b-instruct              | fp8   | 4xH100 | 7000/1000                    | Token-per-second | 61.81  | 120.41 | 234.06 | 433.33  | 628.37  | 1171.38 | 1621.52 | 1819.35  | 1481.26  | 1466.95  | 1461.61 |
| meta/llama3-70b-instruct              | fp8   | 8xH100 | 7000/1000                    | Token-per-second | 68.82  | 134.09 | 259.51 | 486.32  | 879.34  | 1092.46 | 1894.18 | 2371.35  | 2763.93  | 2686.63  | 2679.6  | 2681.86 |

| Model                                 | Dtype | GPUs   | Input/Output sequence length | Concurrency      | 1      | 2      | 4      | 8       | 16      | 32      | 64      | 128      | 512      | 1024     | 2048    |
| :------:                              | :---: | :----: | :-------:                    | :------:         | :---:  | :---:  | :----: | :----:  | :----:  | :----:  | :----:  | :----:   | :----:   | :----:   | :----:  |
| meta/llama-3_1-70b-instruct           | fp16  | 4xH100 | 7000/1000                    | Token-per-second | 32.0   | 61.01  | 107.95 | 173.25  | 232.85  | 314.08  | 330.88  | 327.15   | 328.77   | 332.73   | 329.02  |

| Model                                 | Dtype | GPUs   | Input/Output sequence length | Concurrency      | 1      | 2      | 4      | 8       | 16      | 32      | 64      | 128      | 512      | 1024     | 2048    |
| :------:                              | :---: | :----: | :-------:                    | :------:         | :---:  | :---:  | :----: | :----:  | :----:  | :----:  | :----:  | :----:   | :----:   | :----:   | :----:  |
| mistralai/mixtral-8x22b-instruct-v0.1 | fp16  | 8xH100 | 7000/1000                    | Token-per-second | 59.73  | 106.63 | 179.55 | 316.53  | 562.77  | 851.0   | 1113.7  | 1174.63  | 1176.42  | 1173.39  | 1174.59 | 1192.65 |

