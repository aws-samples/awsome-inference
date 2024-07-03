#!/bin/bash

# Concurrency value
concurrency_value=3000

# Number of times to run the test
num_runs=10

for ((i=1; i<=$num_runs; i++)); do
    iteration_success=false

    while [ "$iteration_success" == false ]; do
        # Replace the concurrency value in the genai-perf.yaml file
        sed -i "s/--concurrency [0-9]*/--concurrency ${concurrency_value}/g" ./nim-deploy/helm/genai-perf.yaml

        # Apply the updated genai-perf.yaml file
        kubectl apply -f ./nim-deploy/helm/genai-perf.yaml

        # Get the new pod name from the deployment
        new_pod_name=$(kubectl get pods --selector=app=genai-perf -o jsonpath="{.items[0].metadata.name}")

        # Wait for the new pod to be in the Running state
        start_time=$(date +%s)
        while true; do
            pod_status=$(kubectl get pod "$new_pod_name" --output=jsonpath='{.status.phase}')
            if [ "$pod_status" == "Running" ]; then
                break
            fi
            current_time=$(date +%s)
            elapsed_time=$((current_time - start_time))
            if [ $elapsed_time -gt 30 ]; then
                echo "Pod $new_pod_name is not in the Running state after 30 seconds. Deleting deployment and reapplying..."
                kubectl delete deployment genai-perf
                kubectl apply -f ./nim-deploy/helm/genai-perf.yaml
                new_pod_name=$(kubectl get pods --selector=app=genai-perf -o jsonpath="{.items[0].metadata.name}")
                start_time=$(date +%s)
            fi
            echo "Waiting for the pod $new_pod_name to be in the Running state..."
            sleep 5
        done

        echo "Pod $new_pod_name is in the Running state."

        sleep 15

        # Copy the JSON file into the local system
        kubectl cp "${new_pod_name}:/workspace/my_profile_export.json" "./benchmarking/constant_concurrency/json/my_profile_${concurrency_value}_run_${i}.json" || {
            echo "Error copying JSON file for concurrency value $concurrency_value (run $i). Rerunning iteration..."
            kubectl delete deployment genai-perf
            continue
        }

        # Copy the CSV file into the local system
        kubectl cp "${new_pod_name}:/workspace/my_profile_export_genai_perf.csv" "./benchmarking/constant_concurrency/csv/my_profile_${concurrency_value}_run_${i}.csv" || {
            echo "Error copying CSV file for concurrency value $concurrency_value (run $i). Rerunning iteration..."
            kubectl delete deployment genai-perf
            continue
        }

        # Check if both files exist
        if [ -f "./benchmarking/constant_concurrency/json/my_profile_${concurrency_value}_run_${i}.json" ] && [ -f "./benchmarking/constant_concurrency/csv/my_profile_${concurrency_value}_run_${i}.csv" ]; then
            echo "JSON and CSV files for concurrency value $concurrency_value (run $i) have been copied successfully."
            iteration_success=true
        else
            echo "Error: One or both files are missing for concurrency value $concurrency_value (run $i)."
            kubectl delete deployment genai-perf
        # i = $((i - 1))
        fi
    done
    
    # Clean up the pod
    kubectl delete deployment genai-perf
    sleep 5
done

echo "Benchmarking tests completed for concurrency value $concurrency_value."
