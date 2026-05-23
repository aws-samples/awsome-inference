# Reproduce: rev7 LIBFABRIC-forced PASS

**Goal:** Verify the LIBFABRIC backend override fixes the rev7 NIXL UCX
crash. This is the smallest-possible-diff reproduction of the fix.

## Environment

| Item | Value |
|---|---|
| Image | `${ECR_REGISTRY}/dynamo-efa:9467d1460c71` (rev7) |
| Cluster | EKS HyperPod, p5.48xlarge × 2 |
| Model | `meta-llama/Llama-3.1-8B-Instruct` |

## Reproduce

1. Set parameters and ensure cluster prereqs met (see
   `../PREREQUISITES.md`):
   ```bash
   export ECR_REGISTRY="<your registry>"
   export IMAGE_TAG="9467d1460c71"
   ```

2. Take the as-deployed manifest from the FAIL baseline and ADD the
   LIBFABRIC override:
   ```bash
   sed -e 's|058264135704\.dkr\.ecr\.us-east-2\.amazonaws\.com|${ECR_REGISTRY}|g' \
     ../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/artifacts/09-dgd-as-deployed.yaml \
     | python3 -c "import sys; t=sys.stdin.read(); \
         t = t.replace(\
           '\"kv_role\":\"kv_both\"}', \
           '\"kv_role\":\"kv_both\",\"kv_connector_extra_config\":{\"backends\":[\"LIBFABRIC\"]}}'); \
         print(t)" \
     | envsubst '${ECR_REGISTRY} ${IMAGE_TAG}' \
     | kubectl apply -f -
   ```

3. Wait for 3/3 Ready (~3 min cold).

4. Verify decode worker did NOT crash:
   ```bash
   kubectl get pods -n default -l "nvidia.com/dynamo-graph-deployment-name=dynamo-combined-vllm"
   # All 3 should be Running, restart count = 0
   ```

5. Hit `/v1/completions` — should succeed:
   ```bash
   SVC=$(kubectl get svc -n default dynamo-combined-vllm-frontend -o jsonpath='{.spec.clusterIP}')
   curl -X POST http://$SVC:8000/v1/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"The capital of France is","max_tokens":20}' \
     -w "\nHTTP=%{http_code} TIME=%{time_total}s\n"
   # expected: HTTP=200 in ~2 seconds
   ```

## Comparison

Run this AFTER reproducing the FAIL in
`../2026-05-21T1500Z-rev7-baseline-nixl-ucx-rootcause/REPRODUCE.md`.
The two together prove cause + effect.

## Cleanup

```bash
kubectl delete dgd dynamo-combined-vllm -n default
```
