#! /bin/bash
kubectl apply -f genai-perf.yaml
sleep 5
# Get genai-perf pod name
new_pod_name=$(kubectl get pods --selector=app=genai-perf -o jsonpath="{.items[0].metadata.name}")

# Copy file
echo "genai-perf pod name:\t ${new_pod_name}"
kubectl logs -f $new_pod_name
