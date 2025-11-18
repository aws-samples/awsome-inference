# TRT-LLM Benchmark Results

**Date**: 2025-11-18 19:13:02
**Deployment**: trtllm-disagg-qwen-full
**Namespace**: dynamo-cloud
**Model**: Qwen/Qwen2.5-0.5B-Instruct

---

## System Configuration


---

## Benchmark Results

### Test 1: Short Prompt (50 tokens)

- **Duration**: .131210321s
- **Prompt Tokens**: 6
- **Completion Tokens**: 50
- **Total Tokens**: 56
- **Throughput**: 381.06 tokens/sec
- **Max Tokens Requested**: 50

**Sample Output** (first 200 chars):
```
 I'm a beginner in Python and I'm trying to create a program that can find the maximum value in a list of numbers. Can you help me with that? Sure, I can help you with that! Here's a Python program th...
```

### Test 2: Short Prompt (150 tokens)

- **Duration**: .322301308s
- **Prompt Tokens**: 6
- **Completion Tokens**: 150
- **Total Tokens**: 156
- **Throughput**: 465.40 tokens/sec
- **Max Tokens Requested**: 150

**Sample Output** (first 200 chars):
```
 I'm a beginner in Python and I'm trying to create a program that can find the maximum value in a list of numbers. Can you help me with that? Sure, I can help you with that! Here's a Python program th...
```

### Test 3: Medium Prompt (100 tokens)

- **Duration**: .212671773s
- **Prompt Tokens**: 25
- **Completion Tokens**: 100
- **Total Tokens**: 125
- **Throughput**: 470.20 tokens/sec
- **Max Tokens Requested**: 100

**Sample Output** (first 200 chars):
```
 Additionally, provide an example of a real-world application of neural networks in image recognition, such as the use of convolutional neural networks (CNNs) in computer vision tasks. Finally, discus...
```

### Test 4: Long Prompt (50 tokens)

- **Duration**: .129364922s
- **Prompt Tokens**: 64
- **Completion Tokens**: 50
- **Total Tokens**: 114
- **Throughput**: 386.50 tokens/sec
- **Max Tokens Requested**: 50

**Sample Output** (first 200 chars):
```
 Finally, analyze the ethical considerations and potential future directions of AI research and development, including the role of AI in healthcare, education, and society as a whole. The history of a...
```

### Test 5: Latency Test (5 iterations)

- **Iterations**: 5
- **Successful Requests**: 5
- **Failed Requests**: 0
- **Average Latency**: .126s
- **Total Duration**: .630752291s


---

## Deployment Information

### Pod Details

```

```

### Deployment Configuration

```
apiVersion: nvidia.com/v1alpha1
kind: DynamoGraphDeployment
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"nvidia.com/v1alpha1","kind":"DynamoGraphDeployment","metadata":{"annotations":{},"name":"trtllm-disagg-qwen-full","namespace":"dynamo-cloud"},"spec":{"services":{"Frontend":{"componentType":"frontend","dynamoNamespace":"trtllm-disagg-qwen-full","envs":[{"name":"DYN_ROUTER_MODE","value":"kv"}],"extraPodSpec":{"mainContainer":{"image":"058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full","imagePullPolicy":"IfNotPresent"}},"replicas":1},"TrtllmDecodeWorker":{"componentType":"worker","dynamoNamespace":"trtllm-disagg-qwen-full","envs":[{"name":"NATS_URL","value":"nats://dynamo-platform-nats.dynamo-cloud:4222"},{"name":"ETCD_URL","value":"http://dynamo-platform-etcd.dynamo-cloud:2379"},{"name":"LC_ALL","value":"C.UTF-8"},{"name":"LANG","value":"C.UTF-8"},{"name":"PYTHONIOENCODING","value":"utf-8"}],"extraPodSpec":{"mainContainer":{"args":["# Patch Triton's driver.py to handle non-UTF-8 characters in ldconfig output\nTRITON_DRIVER=\"/opt/venv/lib/python3.12/site-packages/triton/backends/nvidia/driver.py\"\nif [ -f \"$TRITON_DRIVER\" ]; then\n  echo \"Patching Triton driver.py for Unicode handling...\"\n  sed -i 's/subprocess\\.check_output(\\[.\\/sbin\\/ldconfig., .-p.\\])\\.decode()/subprocess.check_output([\"\\/sbin\\/ldconfig\", \"-p\"]).decode(\"utf-8\", errors=\"replace\")/g' \"$TRITON_DRIVER\"\n  echo \"Patch applied successfully\"\nfi\n# Start the TRT-LLM decode worker with config file containing cache_transceiver_config\nexec python3 -m dynamo.trtllm \\\n  --model-path Qwen/Qwen2.5-0.5B-Instruct \\\n  --disaggregation-mode decode \\\n  --extra-engine-args /config/trtllm-decode-config.yaml\n"],"command":["/bin/bash","-c"],"image":"058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full","imagePullPolicy":"IfNotPresent","volumeMounts":[{"mountPath":"/config","name":"trtllm-config","readOnly":true}],"workingDir":"/workspace/examples/backends/trtllm"},"volumes":[{"configMap":{"name":"trtllm-config"},"name":"trtllm-config"}]},"replicas":2,"resources":{"limits":{"gpu":"1"},"requests":{"cpu":"4","gpu":"1","memory":"16Gi"}},"subComponentType":"decode"},"TrtllmPrefillWorker":{"componentType":"worker","dynamoNamespace":"trtllm-disagg-qwen-full","envs":[{"name":"NATS_URL","value":"nats://dynamo-platform-nats.dynamo-cloud:4222"},{"name":"ETCD_URL","value":"http://dynamo-platform-etcd.dynamo-cloud:2379"},{"name":"LC_ALL","value":"C.UTF-8"},{"name":"LANG","value":"C.UTF-8"},{"name":"PYTHONIOENCODING","value":"utf-8"}],"extraPodSpec":{"mainContainer":{"args":["# Patch Triton's driver.py to handle non-UTF-8 characters in ldconfig output\nTRITON_DRIVER=\"/opt/venv/lib/python3.12/site-packages/triton/backends/nvidia/driver.py\"\nif [ -f \"$TRITON_DRIVER\" ]; then\n  echo \"Patching Triton driver.py for Unicode handling...\"\n  sed -i 's/subprocess\\.check_output(\\[.\\/sbin\\/ldconfig., .-p.\\])\\.decode()/subprocess.check_output([\"\\/sbin\\/ldconfig\", \"-p\"]).decode(\"utf-8\", errors=\"replace\")/g' \"$TRITON_DRIVER\"\n  echo \"Patch applied successfully\"\nfi\n# Start the TRT-LLM prefill worker with config file containing cache_transceiver_config\nexec python3 -m dynamo.trtllm \\\n  --model-path Qwen/Qwen2.5-0.5B-Instruct \\\n  --disaggregation-mode prefill \\\n  --extra-engine-args /config/trtllm-prefill-config.yaml\n"],"command":["/bin/bash","-c"],"image":"058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full","imagePullPolicy":"IfNotPresent","volumeMounts":[{"mountPath":"/config","name":"trtllm-config","readOnly":true}],"workingDir":"/workspace/examples/backends/trtllm"},"volumes":[{"configMap":{"name":"trtllm-config"},"name":"trtllm-config"}]},"replicas":2,"resources":{"limits":{"gpu":"1"},"requests":{"cpu":"4","gpu":"1","memory":"16Gi"}},"subComponentType":"prefill"}}}}
  creationTimestamp: "2025-11-18T18:57:01Z"
  finalizers:
  - nvidia.com/finalizer
  generation: 3
  name: trtllm-disagg-qwen-full
  namespace: dynamo-cloud
  resourceVersion: "114774527"
  uid: c3e6fe96-72db-4125-aa74-2a095a4dba28
spec:
  services:
    Frontend:
      componentType: frontend
      dynamoNamespace: trtllm-disagg-qwen-full
      envs:
      - name: DYN_ROUTER_MODE
        value: kv
      extraPodSpec:
        mainContainer:
          image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full
          imagePullPolicy: IfNotPresent
          name: ""
          resources: {}
      replicas: 1
    TrtllmDecodeWorker:
      componentType: worker
      dynamoNamespace: trtllm-disagg-qwen-full
      envs:
      - name: NATS_URL
        value: nats://dynamo-platform-nats.dynamo-cloud:4222
      - name: ETCD_URL
        value: http://dynamo-platform-etcd.dynamo-cloud:2379
      - name: LC_ALL
        value: C.UTF-8
      - name: LANG
        value: C.UTF-8
      - name: PYTHONIOENCODING
        value: utf-8
      extraPodSpec:
        mainContainer:
          args:
          - |
            # Patch Triton's driver.py to handle non-UTF-8 characters in ldconfig output
            TRITON_DRIVER="/opt/venv/lib/python3.12/site-packages/triton/backends/nvidia/driver.py"
            if [ -f "$TRITON_DRIVER" ]; then
              echo "Patching Triton driver.py for Unicode handling..."
              sed -i 's/subprocess\.check_output(\[.\/sbin\/ldconfig., .-p.\])\.decode()/subprocess.check_output(["\/sbin\/ldconfig", "-p"]).decode("utf-8", errors="replace")/g' "$TRITON_DRIVER"
              echo "Patch applied successfully"
            fi
            # Start the TRT-LLM decode worker with config file containing cache_transceiver_config
            exec python3 -m dynamo.trtllm \
              --model-path Qwen/Qwen2.5-0.5B-Instruct \
              --disaggregation-mode decode \
              --extra-engine-args /config/trtllm-decode-config.yaml
          command:
          - /bin/bash
          - -c
          image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full
          imagePullPolicy: IfNotPresent
          name: ""
          resources: {}
          volumeMounts:
          - mountPath: /config
            name: trtllm-config
            readOnly: true
          workingDir: /workspace/examples/backends/trtllm
        volumes:
        - configMap:
            name: trtllm-config
          name: trtllm-config
      replicas: 2
      resources:
        limits:
          gpu: "1"
        requests:
          cpu: "4"
          gpu: "1"
          memory: 16Gi
      subComponentType: decode
    TrtllmPrefillWorker:
      componentType: worker
      dynamoNamespace: trtllm-disagg-qwen-full
      envs:
      - name: NATS_URL
        value: nats://dynamo-platform-nats.dynamo-cloud:4222
      - name: ETCD_URL
        value: http://dynamo-platform-etcd.dynamo-cloud:2379
      - name: LC_ALL
        value: C.UTF-8
      - name: LANG
        value: C.UTF-8
      - name: PYTHONIOENCODING
        value: utf-8
      extraPodSpec:
        mainContainer:
          args:
          - |
            # Patch Triton's driver.py to handle non-UTF-8 characters in ldconfig output
            TRITON_DRIVER="/opt/venv/lib/python3.12/site-packages/triton/backends/nvidia/driver.py"
            if [ -f "$TRITON_DRIVER" ]; then
              echo "Patching Triton driver.py for Unicode handling..."
              sed -i 's/subprocess\.check_output(\[.\/sbin\/ldconfig., .-p.\])\.decode()/subprocess.check_output(["\/sbin\/ldconfig", "-p"]).decode("utf-8", errors="replace")/g' "$TRITON_DRIVER"
              echo "Patch applied successfully"
            fi
            # Start the TRT-LLM prefill worker with config file containing cache_transceiver_config
            exec python3 -m dynamo.trtllm \
              --model-path Qwen/Qwen2.5-0.5B-Instruct \
              --disaggregation-mode prefill \
              --extra-engine-args /config/trtllm-prefill-config.yaml
          command:
          - /bin/bash
          - -c
          image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-trtllm:full
          imagePullPolicy: IfNotPresent
          name: ""
          resources: {}
          volumeMounts:
          - mountPath: /config
            name: trtllm-config
            readOnly: true
          workingDir: /workspace/examples/backends/trtllm
        volumes:
        - configMap:
            name: trtllm-config
          name: trtllm-config
      replicas: 2
      resources:
        limits:
          gpu: "1"
        requests:
          cpu: "4"
          gpu: "1"
          memory: 16Gi
      subComponentType: prefill
status:
  conditions:
  - lastTransitionTime: "2025-11-18T19:07:35Z"
    message: All resources are ready
    reason: all_resources_are_ready
    status: "True"
    type: Ready
  state: successful
```

---

## Notes

- All tests use temperature=0.7
- Tests are run sequentially with 2-second delays
- Latency tests include 0.5-second delays between iterations
- Results may vary based on cluster load and resource availability

