#!/bin/bash

# ADD TIME CHANGE THING
# ADD ERROR HANDLING I - 1 THING
# ADD ERROR HANDLING TO REPEAT ITERATION

concurrency_values=(1 10 50 100 500 750 1000 2500 3000 4500 5000)

for concurrency_value in "${concurrency_values[@]}"; do
    iteration_success=false

    while [ "$iteration_success" = false ]; do

        # Replace the concurrency value in the genai-perf.yaml file
        sed -i "s/--concurrency [0-9]*/--concurrency ${concurrency_value}/g" ../nim-deploy/helm/genai-perf.yaml

        # Apply the updated genai-perf.yaml file
        kubectl apply -f ../nim-deploy/helm/genai-perf.yaml

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
                kubectl apply -f ../nim-deploy/helm/genai-perf.yaml
                new_pod_name=$(kubectl get pods --selector=app=genai-perf -o jsonpath="{.items[0].metadata.name}")
                start_time=$(date +%s)
            fi
            echo "Waiting for the pod $new_pod_name to be in the Running state..."
            sleep 5
        done

        echo "Pod $new_pod_name is in the Running state."

        # Extract the pod name from the output
        # pod_name=$(echo "$pod_list" | awk '{print $1}')

        # echo "Pod name: $pod_name"
        # Wait for logs to accumulate
        sleep 15

        # Copy the JSON file into the local system
        kubectl cp "${new_pod_name}:/workspace/my_profile_export.json" "../benchmarking/changing_concurrency/1_gpu/2048/json/my_profile_${concurrency_value}.json" || {
            echo "Error copying JSON file for concurrency value $concurrency_value. Rerunning iteration..."
            kubectl delete deployment genai-perf
            continue
        }

        # Copy the CSV file into the local system
        kubectl cp "${new_pod_name}:/workspace/my_profile_export_genai_perf.csv" "../benchmarking/changing_concurrency/1_gpu/2048/csv/my_profile_${concurrency_value}.csv" || {
            echo "Error copying CSV file for concurrency value $concurrency_value. Rerunning iteration..."
            kubectl delete deployment genai-perf
            continue
        }

        # Check if both files exist to move on to the next test
        if [ -f "../benchmarking/changing_concurrency/1_gpu/2048/json/my_profile_${concurrency_value}.json" ] && [ -f "../benchmarking/changing_concurrency/1_gpu/2048/csv/my_profile_${concurrency_value}.csv" ]; then 
            echo "Both files exist for concurrency value ${concurrency_value}. Moving on to the next test."
            iteration_success=true
        else
            echo "ERROR: One or both files do not exist for concurrency value ${concurrency_value}. Please check the logs."
            kubectl delete deployment genai-perf
        fi
    done
    
    # Clean up the pod
    kubectl delete deployment genai-perf
    sleep 5
done 

echo "All tests completed successfully."    