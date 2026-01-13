# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
ARG CUDA_VERSION=12.8.1
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04

################################ NCCL ########################################

ARG GDRCOPY_VERSION=v2.4.4
ARG EFA_INSTALLER_VERSION=1.42.0
ARG AWS_OFI_NCCL_VERSION=v1.16.0
ARG NCCL_VERSION=v2.27.5-1
ARG NCCL_TESTS_VERSION=v2.16.4

RUN apt-get update -y && apt-get upgrade -y
RUN apt-get remove -y --allow-change-held-packages \
    ibverbs-utils \
    libibverbs-dev \
    libibverbs1 \
    libmlx5-1 \
    libnccl2 \
    libnccl-dev

RUN rm -rf /opt/hpcx \
    && rm -rf /usr/local/mpi \
    && rm -f /etc/ld.so.conf.d/hpcx.conf \
    && ldconfig

ENV OPAL_PREFIX=

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-unauthenticated \
    apt-utils \
    autoconf \
    automake \
    build-essential \
    check \
    cmake \
    curl \
    debhelper \
    devscripts \
    git \
    gcc \
    gdb \
    kmod \
    libsubunit-dev \
    libtool \
    openssh-client \
    openssh-server \
    pkg-config \
    python3-distutils \
    vim \
    python3.10-dev \
    python3.10-venv
RUN apt-get purge -y cuda-compat-*

RUN mkdir -p /var/run/sshd
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config

ENV LD_LIBRARY_PATH=/usr/local/cuda/extras/CUPTI/lib64:/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/aws-ofi-nccl/install/lib:/usr/local/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH

RUN curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
    && python3 /tmp/get-pip.py \
    && pip3 install awscli pynvml

#################################################
## Install NVIDIA GDRCopy
##
## NOTE: if `nccl-tests` or `/opt/gdrcopy/bin/sanity -v` crashes with incompatible version, ensure
## that the cuda-compat-xx-x package is the latest.
RUN git clone -b ${GDRCOPY_VERSION} https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy \
    && cd /tmp/gdrcopy \
    && make prefix=/opt/gdrcopy install

ENV LD_LIBRARY_PATH=/opt/gdrcopy/lib:$LD_LIBRARY_PATH
ENV LIBRARY_PATH=/opt/gdrcopy/lib:$LIBRARY_PATH
ENV CPATH=/opt/gdrcopy/include:$CPATH
ENV PATH=/opt/gdrcopy/bin:$PATH

#################################################
## Install EFA installer
RUN cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar -xf $HOME/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && rm -rf $HOME/aws-efa-installer

###################################################
## Install NCCL
RUN git clone -b ${NCCL_VERSION} https://github.com/NVIDIA/nccl.git  /opt/nccl \
    && cd /opt/nccl \
    && make -j $(nproc) src.build CUDA_HOME=/usr/local/cuda \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_100,code=sm_100"

###################################################
## Install AWS-OFI-NCCL plugin
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y libhwloc-dev
#Switch from sh to bash to allow parameter expansion
SHELL ["/bin/bash", "-c"]
RUN curl -OL https://github.com/aws/aws-ofi-nccl/releases/download/${AWS_OFI_NCCL_VERSION}/aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && tar -xf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && cd aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v} \
    && ./configure --prefix=/opt/aws-ofi-nccl/install \
        --with-mpi=/opt/amazon/openmpi \
        --with-libfabric=/opt/amazon/efa \
        --with-cuda=/usr/local/cuda \
        --enable-platform-aws \
    && make -j $(nproc) \
    && make install \
    && cd .. \
    && rm -rf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v} \
    && rm aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz

SHELL ["/bin/sh", "-c"]

###################################################
## Install NCCL-tests
RUN git clone -b ${NCCL_TESTS_VERSION} https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && make -j $(nproc) \
    MPI=1 \
    MPI_HOME=/opt/amazon/openmpi/ \
    CUDA_HOME=/usr/local/cuda \
    NCCL_HOME=/opt/nccl/build \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_100,code=sm_100"

RUN rm -rf /var/lib/apt/lists/*

## Set Open MPI variables to exclude network interface and conduit.
ENV OMPI_MCA_pml=^ucx            \
    OMPI_MCA_btl=tcp,self           \
    OMPI_MCA_btl_tcp_if_exclude=lo,docker0,veth_def_agent\
    OPAL_PREFIX=/opt/amazon/openmpi \
    NCCL_SOCKET_IFNAME=^docker,lo,veth

## Turn off PMIx Error https://github.com/open-mpi/ompi/issues/7516
ENV PMIX_MCA_gds=hash

## Set LD_PRELOAD for NCCL library
ENV LD_PRELOAD=/opt/nccl/build/lib/libnccl.so

################################ NVSHMEM ########################################

ENV NVSHMEM_DIR=/opt/nvshmem
ENV NVSHMEM_HOME=/opt/nvshmem

# wget https://developer.nvidia.com/downloads/assets/secure/nvshmem/nvshmem_src_3.2.5-1.txz && tar -xvf nvshmem_src_3.2.5-1.txz
# or
# wget https://developer.download.nvidia.com/compute/redist/nvshmem/3.3.9/source/nvshmem_src_cuda12-all-all-3.3.9.tar.gz && tar -xvf nvshmem_src_cuda12-all-all-3.3.9.tar.gz
COPY ./nvshmem_src /nvshmem_src

RUN cd /nvshmem_src \
    && mkdir -p build \
    && cd build \ 
    && cmake \
    -DNVSHMEM_PREFIX=/opt/nvshmem \
    -DCMAKE_INSTALL_PREFIX=/opt/nvshmem \
    \
    -DCUDA_HOME=/usr/local/cuda \
    -DCMAKE_CUDA_ARCHITECTURES="90a;100" \
    \
    -DNVSHMEM_USE_GDRCOPY=1 \
    -DGDRCOPY_HOME=/opt/gdrcopy \
    \
    -DNVSHMEM_USE_NCCL=1 \
    -DNCCL_HOME=/opt/nccl/build \
    -DNCCL_INCLUDE=/opt/nccl/build/include \
    \
    -DNVSHMEM_LIBFABRIC_SUPPORT=1 \
    -DLIBFABRIC_HOME=/opt/amazon/efa \
    \
    -DNVSHMEM_MPI_SUPPORT=1 \
    -DMPI_HOME=/opt/amazon/openmpi \
    \
    -DNVSHMEM_PMIX_SUPPORT=1 \
    -DPMIX_HOME=/opt/amazon/pmix \
    -DNVSHMEM_DEFAULT_PMIX=1 \
    \
    -DNVSHMEM_BUILD_TESTS=1 \
    -DNVSHMEM_BUILD_EXAMPLES=1 \
    -DNVSHMEM_BUILD_HYDRA_LAUNCHER=1 \
    -DNVSHMEM_BUILD_TXZ_PACKAGE=1 \
    \
    -DNVSHMEM_IBRC_SUPPORT=1 \
    -DNVSHMEM_IBGDA_SUPPORT=1 \
    \
    -DNVSHMEM_TIMEOUT_DEVICE_POLLING=0 \
    .. \
    && make -j$(nproc) \
    && make install

ENV PATH=/opt/nvshmem/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/nvshmem/lib:$LD_LIBRARY_PATH
# ENV PATH=/opt/nvshmem/bin:$PATH LD_LIBRARY_PATH=/opt/amazon/pmix/lib:/opt/nvshmem/lib:$LD_LIBRARY_PATH NVSHMEM_REMOTE_TRANSPORT=libfabric NVSHMEM_LIBFABRIC_PROVIDER=efa

################################ Python ########################################

RUN command -v python >/dev/null 2>&1 || ln -s "$(command -v python3)" /usr/bin/python

################################ venv ########################################

RUN python3 -m venv /venv
ENV PATH="/venv/bin:$PATH"

################################ extra packages ########################################

RUN pip install ninja numpy cmake pytest blobfile

################################ PyTorch ########################################

ARG TORCH_VERSION=2.7.1

RUN pip install torch==${TORCH_VERSION} --index-url https://download.pytorch.org/whl/cu128

################################ vLLM ########################################

ARG VLLM_VERSION=0.10.1.1

# RUN pip install vllm==${VLLM_VERSION}

RUN git clone https://github.com/vllm-project/vllm.git /vllm \
    && cd /vllm \
    && git checkout v${VLLM_VERSION} \
    && python use_existing_torch.py \
    && pip install -r requirements/build.txt \
    && pip install --no-build-isolation -e .

################################ flashInfer and flash-attn ########################################

RUN pip install flashinfer-python

RUN pip install flash-attn --no-build-isolation

################################ PPLX-KERNELS ########################################

# see: https://github.com/vllm-project/vllm/tree/main/tools/ep_kernels
# see: https://github.com/pbelevich/pplx-kernels-benchmark

ARG PPLX_KERNELS_COMMIT=12cecfda252e4e646417ac263d96e994d476ee5d

RUN git clone https://github.com/ppl-ai/pplx-kernels.git /pplx-kernels \
    && cd /pplx-kernels \
    && git checkout ${PPLX_KERNELS_COMMIT}
# COPY pplx-kernels /pplx-kernels

RUN cd /pplx-kernels \
    && TORCH_CUDA_ARCH_LIST="9.0a+PTX;10.0" python3 setup.py bdist_wheel \
    && pip install dist/*.whl

ENV PYTHONPATH=/pplx-kernels

################################ DeepGEMM ########################################

# see: https://github.com/deepseek-ai/DeepGEMM#installation

ARG DEEPGEMM_COMMIT=ea9c5d9270226c5dd7a577c212e9ea385f6ef048

RUN git clone https://github.com/deepseek-ai/DeepGEMM.git /DeepGEMM \
    && cd /DeepGEMM \
    && git checkout ${DEEPGEMM_COMMIT} \
    && git submodule update --init --recursive \
    && ./install.sh

################################ DeepEP ########################################

ARG DEEPEP_COMMIT=c18eabdebf1381978ff884d278f6083a6153be3f

RUN git clone https://github.com/deepseek-ai/DeepEP.git /DeepEP \
    && cd /DeepEP \
    && git checkout ${DEEPEP_COMMIT} \
    && TORCH_CUDA_ARCH_LIST="9.0a+PTX;10.0" pip install .
