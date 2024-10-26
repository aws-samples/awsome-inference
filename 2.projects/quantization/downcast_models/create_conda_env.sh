#!/bin/bash

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

source ./miniconda3/bin/activate

conda create -n quant  python=3.11

source activate quant

conda install -y pytorch=2.4.1 torchvision torchaudio transformers datasets fsspec=2023.9.2 pytorch-cuda=12.1 "numpy=1.*" -c pytorch -c nvidia
