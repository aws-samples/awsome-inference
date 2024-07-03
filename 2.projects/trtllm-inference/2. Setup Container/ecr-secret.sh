#!/bin/bash
kubectl create secret docker-registry ecr-secret \
    --docker-server=123456789012.dkr.ecr.us-east-2.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password)
