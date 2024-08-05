#!/bin/bash

# Deploy the KubeRay operator with the Helm chart repository
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

#Install both CRDs and Kuberay operator v1.1.0
helm install kuberay-operator kuberay/kuberay-operator --version 1.1.0

# Kuberay operator pod will be deployed onto head pod
kubectl get pods 