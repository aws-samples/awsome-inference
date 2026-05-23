# Reproduce: rev7 NIXL UCX-default crash (FAIL)

**Goal:** Reproduce the `NIXL_ERR_BACKEND` decode-worker crash on a
stock NixlConnector config to verify the bug is still present.

This is the FAIL experiment. If you reproduce the crash, the bug is
still upstream-unfixed (as of vLLM 0.x bundled with Dynamo 1.1.0). If
you do NOT reproduce the crash, vLLM has shipped a fix and our
`kv_connector_extra_config:{backends:["LIBFABRIC"]}` workaround can be
removed.

## Environment

| Item | Value |
|---|---|
| Image | `${ECR_REGISTRY}/dynamo-efa:9467d1460c71` (rev7) — predecessor of rev8 working image |
| Cluster | EKS HyperPod, p5.48xlarge × 2 |
| Model | `meta-llama/Llama-3.1-8B-Instruct` |
| Backend (deliberately wrong) | UCX (default) |

## Reproduce

1. Set parameters:
   ```bash
   export ECR_REGISTRY="<your registry>"
   export IMAGE_TAG="9467d1460c71"
   ```

2. Apply the as-deployed manifest from `artifacts/09-dgd-as-deployed.yaml`,
   substituting registry/tag. (NOT the LIBFABRIC-forced version — for this
   reproduction we WANT the UCX-default crash.)
   ```bash
   sed -e 's|058264135704\.dkr\.ecr\.us-east-2\.amazonaws\.com|${ECR_REGISTRY}|g' \
       artifacts/09-dgd-as-deployed.yaml | \
   envsubst '${ECR_REGISTRY} ${IMAGE_TAG}' | \
   kubectl apply -f -
   ```

3. Wait for 3/3 Ready (~3 min cold).

4. Hit `/v1/models` first (this works — KubeDiscoveryClient is
   independent of NIXL):
   ```bash
   SVC=$(kubectl get svc -n default dynamo-combined-vllm-frontend -o jsonpath='{.spec.clusterIP}')
   curl http://$SVC:8000/v1/models
   # expected: model returned
   ```

5. Hit `/v1/completions` and watch decode crash:
   ```bash
   curl -X POST http://$SVC:8000/v1/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"Hello","max_tokens":5}'
   # expected: HTTP 500 within ~1 second
   ```

6. Tail decode worker log to see the root cause:
   ```bash
   kubectl logs -n default -l "nvidia.com/dynamo-component=DecodeWorker" --tail=200 | grep -i "nixl_err\|loadRemoteMD\|backend"
   # expected: NIXL_ERR_BACKEND from loadRemoteMD()
   ```

## What you should see

The DecodeWorker pod will go from `1/1 Running` to `0/1 Error` or stay
running but become unresponsive. The crash trace in the log matches
`artifacts/05-decode-crash.log`.

## Cleanup

```bash
kubectl delete dgd dynamo-combined-vllm -n default
```

## What to do AFTER reproducing

Apply the LIBFABRIC fix and validate with
`../2026-05-21T1539Z-rev7-libfabric-forced-PASS/REPRODUCE.md`.
