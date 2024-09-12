# NIM Test Inference Results

The test inference results are only used internally as a baseline to compare the relative performance between models, quantization, and number of GPUs. 


### Table of Summary

| NGC name              | Image tag | Datatype | Instance # / GPU # | Status |
| :---------------- | :------: | ----: | ----: | ----: |
| [llama-3-8-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama3-8b-instruct)                       | 1.0.0 | fp16 | 1x g5 / 1x A10  |     |
|                                                                                                                              | 1.1.1 | fp16 | 1x g5 / 1x A10  |     |
|                                                                                                                              | 1.1.1 | fp8  | 1x p5 / 1x H100 |     |
| [llama-3-70b-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama3-70b-instruct)                    | 1.0.0 | fp8  | 1x p5 / 4x H100 |     |
|                                                                                                                              | 1.1.1 | fp8  | 1x p5 / 8x H100 |     |
| [llama-3.1-8-base](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama-3.1-8b-base)                          | 1.1.2 | fp16 | 1x p5 / 1x H100 | WIP |
|                                                                                                                              | 1.1.2 | fp8  | 1x p5 / 1x H100 | WIP |
| [llama-3.1-8-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama-3.1-8b-instruct)                  | 1.1.2 | fp16 | 1x p5 / 1x H100 | WIP |
|                                                                                                                              | 1.1.2 | fp8  | 1x p5 / 1x H100 | WIP |
| [llama-3.1-70b-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama-3.1-70b-instruct)               | 1.1.2 | fp16 | 1x p5 / 4x H100 |     |
|                                                                                                                              | 1.1.2 | fp8  | 1x p5 / 4x H100 | WIP |
| [llama-3.1-405b-instruct](https://catalog.ngc.nvidia.com/orgs/nim/teams/meta/containers/llama-3.1-405b-instruct)             | 1.1.2 | fp16 | 2x p5 / 8x H100 | WIP |
|                                                                                                                              | 1.1.2 | fp8  | 1x p5 / 8x H100 | WIP |
| [Mixtral-8x22B-Instruct-v0.1](https://catalog.ngc.nvidia.com/orgs/nim/teams/mistralai/containers/mixtral-8x22b-instruct-v01) | 1.0.0 | fp16 | 1x p5 / 8x H100 |     |




### Testings results

#### Llama3-8B-Instruct

| Model                   | Dtype | GPUs   | Input/Output sequence length | Concurrency              | 1      | 2      | 4      | 8       | 16      | 32     | 64      | 128      | 512      | 1024     | 2048    |
| :------:                | :---: | :----: | :-------:                    | :------:                 | :---:  | :---:  | :----: | :----:  | :----:  | :----: | :----:  | :----:   | :----:   | :----:   | :----:  |
| meta/llama3-8b-instruct | fp16  | 1xA10  | 200/114                      | Token-per-second         | 33.59  | 67.88  | 132.63 | 249.43  | 444.14  | 748.54 | 751.67  | 751.21   | 750.92   | 746.93   | 751.75  |
|                         |       |        |                              | Time-to-first-token(sec) | 0.1    | 0.11   | 0.18   | 0.35    | 0.61    | 1.37   | 6.86    | 17.41    | 65.18    | 86.89    | 84.07   |
| meta/llama3-8b-instruct | fp16  | 2xA10  | 200/114                      | Token-per-second         | 61.3   | 114.71 | 214.81 | 366.1   | 603.76  | 922.2  | 924.95  | 927.09   | 926.53   | 925.3    | 924.51  |
|                         |       |        |                              | Time-to-first-token(sec) | 0.06   | 0.1    | 0.18   | 0.36    | 0.73    | 1.45   | 5.93    | 14.59    | 56.39    | 84.46    | 83.91   |
| meta/llama3-8b-instruct | fp8   | 1xH100 | 200/114                      | Token-per-second         | 221.89 | 434.89 | 852.19 | 1634.56 | 2770.71 | 4948.9 | 7815.08 | 10215.99 | 10811.09 | 11956.25 | 11395.5 |
|                         |       |        |                              | Time-to-first-token(sec) | 0.01   | 0.01   | 0.02   | 0.03    | 0.04    | 0.06   | 0.1     | 0.22     | 0.64     | 3.46     | 3.45    |


#### Llama3-70B-Instruct

| Model                    | Dtype | GPUs   | Input/Output sequence length | Concurrency              | 1     | 2      | 4      | 8      | 16     | 32      | 64      | 128     | 512     | 1024    | 2048    |
| :------:                 | :---: | :----: | :-------:                    | :------:                 | :---: | :---:  | :----: | :----: | :----: | :----:  | :----:  | :----:  | :----:  | :----:  | :----:  |
| meta/llama3-70b-instruct | fp8   | 4xH100 | 7000/1000                    | Token-per-second         | 61.81 | 120.41 | 234.06 | 433.33 | 628.37 | 1171.38 | 1621.52 | 1819.35 | 1481.26 | 1466.95 | 1461.61 |
|                          |       |        |                              | Time-to-first-token(sec) | 0.34  | 0.5    | 1.06   | 1.83   | 2.72   | 3.2     | 4.22    | 7.67    | 67.18   | 114.91  | 115.95  |
| meta/llama3-70b-instruct | fp8   | 8xH100 | 7000/1000                    | Token-per-second         | 68.82 | 134.09 | 259.51 | 486.32 | 879.34 | 1092.46 | 1894.18 | 2371.35 | 2686.63 | 2679.6  | 2681.86 |
|                          |       |        |                              | Time-to-first-token(sec) | 0.26  | 0.37   | 0.77   | 1.31   | 1.87   | 2.26    | 2.83    | 4.87    | 74.38   | 159.91  | 159.45  |


#### Llama3.1-70B-Instruct

| Model                       | Dtype | GPUs   | Input/Output sequence length | Concurrency              | 1     | 2     | 4      | 8      | 16     | 32     | 64     | 128    | 512    | 1024   | 2048   |
| :------:                    | :---: | :----: | :-------:                    | :------:                 | :---: | :---: | :----: | :----: | :----: | :----: | :----: | :----: | :----: | :----: | :----: |
| meta/llama-3_1-70b-instruct | fp16  | 4xH100 | 7000/1000                    | Token-per-second         | 32.0  | 61.01 | 107.95 | 173.25 | 232.85 | 314.08 | 330.88 | 327.15 | 328.77 | 332.73 | 329.02 |
|                             |       |        |                              | Time-to-first-token(sec) | 0.54  | 0.57  | 0.58   | 0.63   | 0.73   | 0.97   | 16.82  | 60.95  | 256.17 | 343.76 | 342.66 |


#### Mixtral-8x22B-Instruct

| Model                                 | Dtype | GPUs   | Input/Output sequence length | Concurrency              | 1     | 2      | 4      | 8      | 16     | 32     | 64     | 128     | 512     | 1024    | 2048    |
| :------:                              | :---: | :----: | :-------:                    | :------:                 | :---: | :---:  | :----: | :----: | :----: | :----: | :----: | :----:  | :----:  | :----:  | :----:  |
| mistralai/mixtral-8x22b-instruct-v0.1 | fp16  | 8xH100 | 7000/1000                    | Token-per-second         | 59.73 | 106.63 | 179.55 | 316.53 | 562.77 | 851.0  | 1113.7 | 1174.63 | 1173.39 | 1174.59 | 1192.65 |
|                                       |       |        |                              | Time-to-first-token(sec) | 0.26  | 0.38   | 0.79   | 1.69   | 2.7    | 3.63   | 4.69   | 26.49   | 135.58  | 135.44  | 138.61  |

