# Stage 1: Build the application
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04 AS build
RUN mkdir /tensorrt
WORKDIR /tensorrt
COPY . .
RUN dpkg --configure -a
RUN apt-get update && apt-get -y install python3.10 python3-pip openmpi-bin libopenmpi-dev git
RUN pip3 install -r requirements.txt
RUN chmod +x 1.install_git_and_gitlfs_and_others.sh 2.install_trtllm_and_triton.sh 3.local_inference.sh
RUN ./1.install_git_and_gitlfs_and_others.sh 
RUN ./2.install_trtllm_and_triton.sh 

# # Stage 2: Start up the healthcheck server
# FROM python:3.10-slim
# WORKDIR /tensorrt
# COPY --from=build /tensorrt ./
# RUN chmod +x healthcheck.py
# ENV FLASK_APP=healthcheck.py
# CMD ["python3", "healthcheck.py", "&"]

# Stage 2: Serve the application
FROM nvcr.io/nvidia/tritonserver:24.04-trtllm-python-py3
WORKDIR /tensorrt
COPY --from=build /tensorrt ./
ENTRYPOINT [ "./3.local_inference.sh" ] 
EXPOSE 8888
EXPOSE 8000
EXPOSE 8001
EXPOSE 8002
EXPOSE 8080