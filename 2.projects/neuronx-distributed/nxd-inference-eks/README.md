# NeuronX Distributed Inference on EKS

This example demonstrates deploying Large Language Models using **NeuronX Distributed Inference (NxDI)** on Amazon EKS with AWS Trainium instances. The deployment supports both standard inference and speculative decoding. For the purpose of this example, we use the Qwen3 family of models but other popular model architectures are also supported with Neuron and can be used with this example and with supported kernels.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Amazon EKS Cluster                       │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  Download Job   │  │   Compilation   │  │   Monitoring │ │
│  │  (HF → EFS)     │  │      Job        │  │   DaemonSet  │ │
│  │  • Target model │  │  • NxDI compile │  │  • Neuron    │ │
│  │  • Draft model  │  │  • Spec / NoSpec│  │    Monitor   │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│                                                             │
│  ┌─────────────────┐                                        │
│  │  Inference      │                                        │
│  │  Deployment     │                                        │
│  │  • vLLM Server  │                                        │
│  │  • LoadBalancer │                                        │
│  └─────────────────┘                                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Shared EFS Storage                         ││
│  │  • /shared/model_hub/* (downloads)                      ││
│  │  • /shared/compiled_models/Qwen3/* (neffs)              ││
│  │  • Logs                                                 ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Kubernetes-native** jobs for **download** and **compile**
- **Speculative decoding** toggle via `ENABLE_SPECULATIVE`
- **Separate compiled outputs** for spec / non-spec (no overwrites)
- **Shared EFS storage** for models, artifacts, and logs
- **Load balancing** and **monitoring** with Neuron Monitor

## Prerequisites

- Follow the steps in `1.infrastructure/0_setup_vpc/vpc-cf-example.yaml` and `1.infrastructure/1_setup_cluster/nxd-inference/Create_EKS_Cluster.md` first to setup your infrastructure.
- `kubectl`, `aws` CLI, and `helm`
- EKS cluster with Trainium nodes and EFS PVC
- A Hugging Face token with access to the target repos

Install Neuron device plugin and (optionally) the scheduler extension:

```bash

helm upgrade --install neuron-helm-chart oci://public.ecr.aws/neuron/neuron-helm-chart --set "npd.enabled=false"
kubectl get ds neuron-device-plugin -n kube-system

helm upgrade --install neuron-helm-chart oci://public.ecr.aws/neuron/neuron-helm-chart \
  --set "scheduler.enabled=true" \
  --set "npd.enabled=false"

```

## Setup

### 1) Clone & Navigate

```bash
git clone https://github.com/aws-samples/awsome-inference.git
cd awsome-inference/2.projects/neuronx-distributed/nxd-inference-eks/
```

### 2) Label Trainium Nodes

```bash
kubectl label nodes -l node.kubernetes.io/instance-type=trn1.32xlarge workload-type=neuron-inference
kubectl taint nodes -l node.kubernetes.io/instance-type=trn1.32xlarge aws.amazon.com/neuron=:NoSchedule
kubectl get nodes -L workload-type,node.kubernetes.io/instance-type
```

### 3) Namespace, Storage, and Secrets

```bash
kubectl create namespace neuron-inference

# Apply EFS storage configuration
kubectl apply -f fused-SD/manifests/storage.yaml -n neuron-inference #this uses the efs filesystem and the storage class you created previously

# Create HF token secret once
# replace YOUR_HF_TOKEN with your actual token (starts with hf_)
kubectl -n neuron-inference create secret generic hf-token \
  --from-literal=HF_TOKEN='YOUR_HF_TOKEN' \
  --dry-run=client -o yaml | kubectl apply -f -

```

## Workflow

> **Two steps:** (1) **Download** both models to EFS, (2) **Compile** with or without speculation.  
> Compiles write to **separate directories** so you can keep both.

### Create a secret once for your HF token:

kubectl -n neuron-inference create secret generic hf-token \
  --from-literal=HF_TOKEN='YOUR_HF_TOKEN'


### Step 1 — Download both models (target + draft)

Apply the **download job** manifest:

```bash
kubectl apply -n neuron-inference -f fused-SD/manifests/model_download.yaml
kubectl -n neuron-inference wait --for=condition=complete job/neuron-model-download --timeout=3600s
kubectl -n neuron-inference logs job/neuron-model-download --tail=200
```

Expected locations after success:

```
/shared/model_hub/${MODEL_DIRNAME}/config.json
/shared/model_hub/${DRAFT_DIRNAME}/config.json
```

Quick verify:

```bash
kubectl -n neuron-inference exec -it <any-running-pod> -- ls -l /shared/model_hub/${MODEL_DIRNAME} | head
```

### Step 2 — Compile (separate outputs for spec vs non-spec)

Apply the **compile job** manifest. Control speculation by editing the `ENABLE_SPECULATIVE` environment variable in the manifest as well as other env vars you would like to set or toggle. The script sets a number of defaults in the ConfigMap:

```bash
# Non-spec compile (kept in /shared/compiled_models/Llama-3.3-70B/nospec_tp32)
kubectl apply -n neuron-inference -f fused-SD/manifests/compile.yaml
kubectl -n neuron-inference wait --for=condition=complete job/neuron-model-compilation --timeout=3600s
kubectl -n neuron-inference logs job/neuron-model-compilation --tail=200

# For speculative compile, edit the manifest to set ENABLE_SPECULATIVE=true, then:
kubectl -n neuron-inference delete job neuron-model-compilation --ignore-not-found
kubectl apply -n neuron-inference -f fused-SD/manifests/compile.yaml
kubectl -n neuron-inference wait --for=condition=complete job/neuron-model-compilation --timeout=3600s
kubectl -n neuron-inference logs job/neuron-model-compilation --tail=200
```

**Output layout (no overwrites):**
```
/shared/compiled_models/Qwen3-32B/
  ├─ nospec_tp32/
  └─ spec_slen7_tp32/
```

### Step 3 — Deploy Inference

**Important:** Before deploying, you must update the compiled model paths in `fused-SD/manifests/fsd-deploy.yaml` to match your compilation parameters. Please make sure that the env vars being set and used by vLLM are consistent with your compile-time input shapes and configs.

The deployment manifest has hardcoded paths that need to match your compile job settings:

```yaml
# In fsd-deploy.yaml, update these env vars to match your compilation:
- name: COMPILED_MODEL_PATH_STD
  value: "/shared/compiled_models/Qwen3-32B/spec_slen7_tp32"  # for speculative
- name: COMPILED_MODEL_PATH_SPEC  
  value: "/shared/compiled_models/Qwen3-32B/nospec_tp32"      # for non-speculative
```

**Path format:** `/shared/compiled_models/{MODEL_NAME}/{mode}_{params}`

Where:
- `{MODEL_NAME}` = your `COMPILED_ROOT` basename (e.g., `Qwen3-32B`)
- `{mode}` = `spec` or `nospec` 
- `{params}` = `slen{SPECULATION_LENGTH}_tp{TP_DEGREE}` for spec, or just `tp{TP_DEGREE}` for nospec

**Examples:**
- TP=32, no speculation: `nospec_tp32`
- TP=32, speculation length 7: `spec_slen7_tp32` 
- TP=16, speculation length 5: `spec_slen5_tp16`

**Quick update command:**
```bash
# For TP=32, SPECULATION_LENGTH=7 (adjust as needed)
sed -i 's|/shared/compiled_models/Qwen3-32B/spec_slen7_tp32|/shared/compiled_models/Qwen3-32B/spec_slen7_tp32|g' fused-SD/manifests/fsd-deploy.yaml
sed -i 's|/shared/compiled_models/Qwen3-32B/nospec_tp32|/shared/compiled_models/Qwen3-32B/nospec_tp32|g' fused-SD/manifests/fsd-deploy.yaml
```

Then apply your inference deployment:

```bash
kubectl apply -n neuron-inference -f fused-SD/manifests/fsd-deploy.yaml
kubectl -n neuron-inference wait --for=condition=available deployment/neuron-llama-inference --timeout=600s
```

### Step 4 — Load Balancing with Application Load Balancer

To expose your inference service externally and distribute traffic across multiple pods, you'll set up an Application Load Balancer (ALB) using the AWS Load Balancer Controller.

#### 4.1 Install AWS Load Balancer Controller

**Prerequisites:**
- Your EKS cluster must have an IAM OIDC identity provider
- The AWS Load Balancer Controller requires specific IAM permissions

**Option A: Using Kubernetes Manifests (Recommended)**

1. Create the IAM policy and service account:
```bash
# Download the IAM policy document
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json

# Create the IAM policy
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# Create service account with IAM role
eksctl create iamserviceaccount \
  --cluster=your-cluster-name \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::ACCOUNT-ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

2. Install the controller:
```bash
# Add the EKS chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=your-cluster-name \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

3. Verify installation:
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Option B: Using Helm (Alternative)**
Follow the [AWS documentation for Helm installation](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html).

#### 4.2 Deploy the Ingress

Once the AWS Load Balancer Controller is installed and running:

```bash
# Apply the ingress configuration
kubectl -n neuron-inference apply -f fused-SD/manifests/neuron-ingress.yaml

# Monitor ingress creation (wait for ADDRESS to appear)
kubectl -n neuron-inference get ingress neuron-qwen-ingress -w
```

The ingress will create an Application Load Balancer that:
- Routes traffic to your inference service pods
- Provides health checks on the `/health` endpoint
- Supports both HTTP and HTTPS traffic
- Automatically scales with your deployment

#### 4.3 Test Your Deployment

Once the ALB is provisioned (this can take 2-3 minutes):

```bash
# Get the ALB hostname
ALB=$(kubectl -n neuron-inference get ing neuron-qwen-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB Endpoint: http://$ALB"

# Test the health endpoint
curl -i "http://$ALB/health"

# List available models
curl -i "http://$ALB/v1/models"

# Test inference with a simple completion
curl -s "http://$ALB/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/shared/model_hub/Qwen3-32B",
    "prompt": "Say hi from vLLM on Neuron.",
    "max_tokens": 64,
    "temperature": 0.7
  }'

# Test with chat completions API
curl -s "http://$ALB/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/shared/model_hub/Qwen3-32B",
    "messages": [{"role": "user", "content": "Hello! How are you?"}],
    "max_tokens": 100
  }'
```
Congratulation!

#### 4.4 Production Considerations

For production deployments, consider:

- **HTTPS/TLS**: Configure SSL certificates using AWS Certificate Manager
- **Custom Domain**: Set up Route 53 records pointing to your ALB
- **WAF Integration**: Add AWS WAF for additional security
- **Access Logging**: Enable ALB access logs for monitoring and debugging
- **Target Group Settings**: Tune health check intervals and thresholds based on your model's startup time

Example ingress with HTTPS:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neuron-qwen-ingress-https
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  rules:
  - host: your-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: neuron-llama-service
            port:
              number: 8000
```

### Step 5 — Deploy Neuron Monitor for Observability

AWS Neuron Monitor provides comprehensive monitoring and observability for your Neuron workloads, including hardware utilization, model performance metrics, and system health indicators.

#### 5.1 Understanding Neuron Monitor

Neuron Monitor offers:
- **Hardware Metrics**: NeuronCore utilization, memory usage, temperature
- **Model Performance**: Inference latency, throughput, queue depth
- **System Health**: Device status, error rates, compilation metrics
- **Integration**: Works with Prometheus, Grafana, CloudWatch, and other monitoring systems

#### 5.2 Deploy Neuron Monitor DaemonSet

The Neuron Monitor runs as a DaemonSet to collect metrics from all Neuron devices across your cluster:

```bash
# Create the Neuron Monitor DaemonSet
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: neuron-monitor
  namespace: neuron-inference
  labels:
    app: neuron-monitor
spec:
  selector:
    matchLabels:
      app: neuron-monitor
  template:
    metadata:
      labels:
        app: neuron-monitor
    spec:
      serviceAccount: neuron-monitor
      hostNetwork: true
      hostPID: true
      containers:
      - name: neuron-monitor
        image: #set latest image
        securityContext:
          privileged: true
        env:
        - name: NEURON_MONITOR_CW_REGION
          value: "us-west-2"  # Change to your region
        - name: NEURON_MONITOR_CW_LOG_GROUP
          value: "/aws/eks/neuron-monitor"
        ports:
        - containerPort: 8080
          name: http-metrics
        - containerPort: 8082
          name: http-health
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: neuron-devices
          mountPath: /dev/neuron0
        - name: tmp
          mountPath: /tmp
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8082
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8082
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      - name: neuron-devices
        hostPath:
          path: /dev/neuron0
      - name: tmp
        hostPath:
          path: /tmp
      nodeSelector:
        workload-type: neuron-inference
      tolerations:
      - key: aws.amazon.com/neuron
        operator: Exists
        effect: NoSchedule
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: neuron-monitor
  namespace: neuron-inference
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT-ID:role/NeuronMonitorRole
---
apiVersion: v1
kind: Service
metadata:
  name: neuron-monitor-service
  namespace: neuron-inference
  labels:
    app: neuron-monitor
spec:
  selector:
    app: neuron-monitor
  ports:
  - name: http-metrics
    port: 8080
    targetPort: 8080
  - name: http-health
    port: 8082
    targetPort: 8082
  type: ClusterIP
EOF
```

#### 5.3 Create IAM Role for CloudWatch Integration

If you want to send metrics to CloudWatch, create an IAM role:

```bash
# Create IAM policy for CloudWatch access
cat <<EOF > neuron-monitor-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the policy
aws iam create-policy \
    --policy-name NeuronMonitorCloudWatchPolicy \
    --policy-document file://neuron-monitor-policy.json

# Create service account with IAM role (replace ACCOUNT-ID and CLUSTER-NAME)
eksctl create iamserviceaccount \
  --cluster=CLUSTER-NAME \
  --namespace=neuron-inference \
  --name=neuron-monitor \
  --role-name=NeuronMonitorRole \
  --attach-policy-arn=arn:aws:iam::ACCOUNT-ID:policy/NeuronMonito
--approve
```
**Verify Neuron Monitor Deployment**

```bash
# Check DaemonSet status
kubectl -n neuron-inference get daemonset neuron-monitor
kubectl -n neuron-inference get pods -l app=neuron-monitor

# View logs
kubectl -n neuron-inference logs -l app=neuron-monitor --tail=50
```

#### 5.5 Configure Prometheus Integration (Optional)

To scrape metrics with Prometheus, add the following ServiceMonitor:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: neuron-monitor
  namespace: neuron-inference
  labels:
    app: neuron-monitor
spec:
  selector:
    matchLabels:
      app: neuron-monitor
  endpoints:
  - port: http-metrics
    interval: 30s
    path: /metrics
EOF
```

#### 5.6 Key Metrics to Monitor

Neuron Monitor exposes several important metrics:

**Hardware Metrics:**
- `neuron_hardware_ecc_events_total`: ECC error events
- `neuron_hardware_memory_used_bytes`: Memory utilization per NeuronCore
- `neuron_hardware_utilization_ratio`: NeuronCore utilization percentage

**Runtime Metrics:**
- `neuron_runtime_inference_latency_seconds`: End-to-end inference latency
- `neuron_runtime_queue_size`: Number of pending inference requests
- `neuron_runtime_throughput_inferences_per_second`: Inference throughput

**Model Metrics:**
- `neuron_model_loaded`: Whether model is successfully loaded
- `neuron_model_inference_errors_total`: Inference error count
- `neuron_execution_latency_seconds`: Model execution time

#### 5.7 Grafana Dashboard

You can import pre-built Grafana dashboards for Neuron monitoring:

```bash
# Download the official Neuron dashboard
curl -o neuron-dashboard.json https://raw.githubusercontent.com/aws-neuron/aws-neuron-samples/master/src/examples/pytorch/neuron_monitor/grafana-dashboard.json

# Import into your Grafana instance via the UI or API
```

#### 5.8 CloudWatch Integration

If using CloudWatch, metrics will appear under the `AWS/Neuron` namespace. You can create CloudWatch alarms for:

- High NeuronCore utilization
- Inference latency spikes  
- Error rate thresholds
- Memory usage alerts

Example CloudWatch alarm:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "High-Neuron-Utilization" \
  --alarm-description "Alert when NeuronCore utilization exceeds 90%" \
  --metric-name neuron_hardware_utilization_ratio \
  --namespace AWS/Neuron \
  --statistic Average \
  --period 300 \
  --threshold 0.9 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

## Troubleshooting
  kubectl -n neuron-inference logs job/neuron-model-download --tail=200
  ```
- Ensure the HF token secret exists and is referenced:
  ```bash
  kubectl -n neuron-inference get secret hf-token
  ```
- Verify the EFS PVC is bound and writable:
  ```bash
  kubectl -n neuron-inference get pvc
  ```

**Compile fails immediately saying “Unrecognized model … config.json”**
- The download likely didn’t complete or the path is wrong. Verify:
  ```bash
  kubectl -n neuron-inference exec -it <pod> -- test -f /shared/model_hub/${MODEL_DIRNAME}/config.json && echo OK
  ```

**Spec compile overwrote non-spec?**
- With the provided manifests, outputs are separated per mode (`nospec_*` vs `spec_*`). If you see overwrites, confirm your `COMPILED_ROOT` and job env vars.

**Inference deployment can't find compiled artifacts**
- Check that the paths in `fsd-deploy.yaml` match your actual compilation output:
  ```bash
  kubectl -n neuron-inference exec -it <pod> -- ls -la /shared/compiled_models/Qwen3-32B/
  ```
- Update the `COMPILED_MODEL_PATH_STD` and `COMPILED_MODEL_PATH_SPEC` env vars to match your TP degree and speculation length.

**Neuron compiler errors**
- These are model/hardware/SDK specific. Re-run with smaller `TP_DEGREE`, confirm SDK image version, or inspect `/shared/compile*.log`. Consider filing an issue with logs.

## Cleanup

```bash
kubectl -n neuron-inference delete job neuron-model-download --ignore-not-found
kubectl -n neuron-inference delete job neuron-model-compilation --ignore-not-found
kubectl -n neuron-inference delete deployment neuron-llama-inference service neuron-llama-service --ignore-not-found
kubectl -n neuron-inference delete pvc efs-models-pvc --ignore-not-found
kubectl delete namespace neuron-inference
```

## References

- [AWS Neuron Documentation](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/) – NxDI & compiler guidance
- [NeuronX Distributed Inference Guide](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/neuronx-distributed/index.html)
- [vLLM Documentation](https://docs.vllm.ai/) – Server flags and deployment considerations
- [Kubernetes Jobs Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [AWS Neuron Helm Charts](https://github.com/aws-neuron/aws-neuron-helm-charts)
- [AWS Trainium Instance Types](https://aws.amazon.com/ec2/instance-types/trn1/)
