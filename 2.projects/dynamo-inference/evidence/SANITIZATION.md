# Evidence sanitization rules

This archive is the **ground truth** for experiments. When evidence is
synced to downstream repos (PR forks, public workshops, customer-facing
docs), this document defines the **mechanical substitutions** that make
the evidence portable while preserving provenance.

## Two-layer principle

1. **`artifacts/` directories are immutable.** They contain the historical
   truth of what we ran — including ECR account numbers, ClusterIPs, node
   hostnames. Sanitization NEVER edits artifacts.

2. **Everything else is parametric.** `manifest.yaml`, `BUILD.md`,
   `REPRODUCE.md`, `derived/<template>.yaml`, READMEs use placeholders
   like `${ECR_REGISTRY}`. Downstream consumers `export` the variables
   for their environment, then run.

## Substitution table

| Variable | Example value (ours) | Where it appears | Sanitization rule for public sync |
|---|---|---|---|
| `${ECR_REGISTRY}` | `${ECR_REGISTRY}` | manifest.yaml, BUILD.md, REPRODUCE.md, derived/*.yaml | **REDACT** — replace with `${ECR_REGISTRY}` placeholder; downstream sets via env or arg |
| `${IMAGE_TAG}` | `520cfc584abb` | manifest.yaml, BUILD.md, REPRODUCE.md | **KEEP** — public; pins the bytes via `image.digest` |
| `${IMAGE_DIGEST}` | `sha256:48e6e3104b523bc1...` | manifest.yaml | **KEEP** — public; the canonical provenance |
| `${AWS_REGION}` | `us-east-2` | BUILD.md, REPRODUCE.md | **KEEP** — generic |
| `${CODEBUILD_PROJECT}` | `dynamo-inference-public` | BUILD.md | **KEEP** — generic name |
| `${CLUSTER_NAME}` | (HyperPod cluster name) | not currently in docs | **REDACT** if added |
| Node hostnames | `hyperpod-i-0a3eb6d3953cceaa7` | artifacts/03-pods.txt, manifest.yaml.hardware.nodes | **OK in artifacts**, **REDACT** in manifest.hardware.nodes (replace with `node-A`, `node-B`) |
| ClusterIPs | `172.20.117.134` | artifacts/02-apply.log, REPRODUCE.md | **OK in artifacts**, **PARAMETRIZE** in REPRODUCE.md (use `kubectl get svc ... -o jsonpath` lookup at run time) |
| `${HF_TOKEN}` | (secret) | PREREQUISITES.md | **NEVER COMMIT** — placeholder only |
| HF model id | `meta-llama/Llama-3.1-8B-Instruct` | manifest.yaml, REPRODUCE.md | **KEEP** — public model |

## Sync workflow (manual today, scripted later)

When copying an experiment from `awesome-inferencing/docs/evidence/` to
a downstream repo:

```bash
# 1. Copy the experiment dir, MINUS artifacts/ if the target is public
rsync -av \
  --exclude=artifacts \
  --exclude=derived/superseded \
  awesome-inferencing/docs/evidence/pr72-rev8/2026-05-22T0550Z-nixlbench-multinode-PASS/ \
  downstream-repo/path/to/evidence/

# 2. (Optional) Sanitize manifest.yaml — strip account-internal fields
yq 'del(.image.ref) | del(.image.build_id) | del(.hardware.nodes) | del(.hardware.cluster)' \
  -i downstream-repo/path/to/evidence/manifest.yaml

# 3. The remaining manifest.yaml + README.md + VERDICT.md + REPRODUCE.md
#    + derived/dgd-template.yaml are already parametric.
```

For richer downstream cases (workshop tutorials, customer docs), also
substitute the prose:

```bash
sed -i 's|058264135704\.dkr\.ecr\.us-east-2\.amazonaws\.com|${ECR_REGISTRY}|g' \
  downstream-repo/path/to/evidence/REPRODUCE.md
sed -i 's|hyperpod-i-[0-9a-f]\+|node-X|g' \
  downstream-repo/path/to/evidence/manifest.yaml
```

## What to NEVER include in public sync

- **AWS account numbers** (12-digit prefix on ECR / IAM / KMS / CodeBuild ARNs)
- **HF tokens, API keys, JWTs, certificates** (any `*-token` env var values)
- **Private IPs in REPRODUCE.md prose** (artifacts OK; prose should derive at run time)
- **Internal cluster names** (replace with generic "your-cluster")
- **Internal Slack/email/Linear references** (move to project-private if needed)

## What to ALWAYS include in public sync

- **Image digest** (`sha256:...`) — provenance pin
- **Git commit SHA** — the exact source state
- **Dockerfile snapshots** in `build-snapshot/` (the actual build inputs)
- **Public model IDs** (Hugging Face)
- **Public package versions** (NCCL, NIXL, libfabric, EFA installer)
- **Public verdicts and numbers** (bandwidth, latency, speedup ratios)

## Why this approach

- **Provenance is preserved**: the digest pins the exact image bytes,
  the build-snapshot pins the exact source. Anyone can verify they
  rebuilt the same thing by comparing digests.
- **Privacy is preserved**: account numbers, hostnames, IPs are
  parametric.
- **artifacts/ is honest**: the as-deployed YAML, the actual logs
  contain the actual values. Future debuggers don't have to guess what
  ran.
- **Downstream is mechanical**: a 3-line `rsync + yq + sed` script
  produces a clean public version.
