# CodeBuild setup — dynamo-inference (public-FROM-only)

After the public-base-only rewrite, the shipping Dockerfiles `FROM` only public
NGC images (`nvcr.io/nvidia/cuda-dl-base`, `nvcr.io/nvidia/ai-dynamo/trtllm-runtime`,
`nvcr.io/nvidia/ai-dynamo/vllm-runtime`). No private ECR dependency means the
CodeBuild architecture collapses to a single project.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ CodePipeline (optional): dynamo-inference                       │
│                                                                 │
│  Source (GitHub) ────►  BUILD (buildspec.yml)  ────►  Push ECR │
│                         + trivy CVE gate                        │
│                         + SBOM upload to S3                     │
└──────────────┬──────────────────────────────────┬───────────────┘
               ▼                                   ▲
        GitHub webhook                             │
                                                   │
                   Private ECR ◄────────────────────
                     awsi-efa-base:<sha>
                     awsi-dynamo-combined-efa:<sha>

                   S3 bucket (optional)
                     s3://dist-sboms/<sha>/sbom/
                     s3://dist-sboms/<sha>/cve/
```

One CodeBuild project + `buildspec.yml`. The 25-min networking stage is
cached via BuildKit `--cache-from` against the previous `:latest` tag in
ECR — warm rebuilds of unchanged `base/**` layers are ~5 min.

---

## Prerequisites

- AWS account with a CodeBuild-capable region (recommended: `us-east-2`)
- GitHub connection to this repo authorized in CodeStar Connections
- IAM user/role to create CloudFormation stacks

---

## One-time bootstrap

### 1. Create private ECR repos (output only — no private base image now)

```bash
REGION=us-east-2
for repo in awsi-efa-base awsi-dynamo-combined-efa; do
  aws ecr create-repository --repository-name "$repo" \
    --region "$REGION" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    || echo "  $repo already exists"
done
```

Apply a lifecycle policy that keeps last 10 SHA-tagged + `latest`, expires
untagged after 1 day:

```bash
cat > /tmp/ecr-lifecycle.json <<'EOF'
{
  "rules": [
    { "rulePriority": 1, "description": "keep mutable tags",
      "selection": { "tagStatus": "tagged", "tagPatternList": ["latest","v*"], "countType": "imageCountMoreThan", "countNumber": 10 },
      "action": { "type": "expire" } },
    { "rulePriority": 2, "description": "keep last 10 SHA-tagged",
      "selection": { "tagStatus": "tagged", "tagPatternList": ["*"], "countType": "imageCountMoreThan", "countNumber": 10 },
      "action": { "type": "expire" } },
    { "rulePriority": 3, "description": "expire untagged",
      "selection": { "tagStatus": "untagged", "countType": "sinceImagePushed", "countUnit": "days", "countNumber": 1 },
      "action": { "type": "expire" } }
  ]
}
EOF

for repo in awsi-efa-base awsi-dynamo-combined-efa; do
  aws ecr put-lifecycle-policy --repository-name "$repo" \
    --region "$REGION" --lifecycle-policy-text file:///tmp/ecr-lifecycle.json
done
```

### 2. Create CodeBuild service role

Trust policy — CodeBuild only:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "codebuild.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

Inline policy (minimum required — tighten Resource scoping in prod):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/codebuild/*"
    },
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeRepositories",
        "ecr:CreateRepository",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": [
        "arn:aws:ecr:us-east-2:058264135704:repository/awsi-efa-base",
        "arn:aws:ecr:us-east-2:058264135704:repository/awsi-dynamo-combined-efa"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject","s3:GetObject"],
      "Resource": "arn:aws:s3:::<your-sbom-bucket>/*"
    }
  ]
}
```

Substitute `058264135704` + `us-east-2` + `<your-sbom-bucket>`.

### 3. Create the CodeBuild project

```bash
aws codebuild create-project \
  --name dynamo-inference \
  --region us-east-2 \
  --source type=GITHUB,location=https://github.com/dmvevents/awsome-inference-1.git,buildspec=2.projects/dynamo-inference/buildspec.yml \
  --artifacts type=NO_ARTIFACTS \
  --environment "type=LINUX_CONTAINER,computeType=BUILD_GENERAL1_2XLARGE,image=aws/codebuild/amazonlinux2-x86_64-standard:5.0,privilegedMode=true,environmentVariables=[
    {name=AWS_ACCOUNT_ID,value=058264135704},
    {name=AWS_DEFAULT_REGION,value=us-east-2},
    {name=ECR_REPO_PREFIX,value=},
    {name=CUDA_ARCH,value=90},
    {name=S3_SBOM_BUCKET,value=s3://your-sbom-bucket/dynamo-inference},
    {name=CVE_ALLOW_CRITICAL,value=0}
  ]" \
  --service-role arn:aws:iam::058264135704:role/CodeBuildDynamoInferenceRole \
  --timeout-in-minutes 120
```

Compute-type notes:
- `BUILD_GENERAL1_2XLARGE` (72 vCPU / 145 GB / 824 GB SSD) — required.
  The combined image is 48 GB and overflows LARGE's 200 GB scratch during
  `exporting layers`. LARGE is also insufficient for the networking build
  (UCX + NIXL + NCCL from source needs ~40 GB peak).
- `privilegedMode: true` — required for Docker-in-Docker. Without this,
  `docker build` errors with `Cannot connect to the Docker daemon`.
- `timeout: 120 min` — cold build takes ~45 min (25 min networking + 15 min
  combined + 5 min scan/push). Warm builds are ~15 min total.

### 4. Trigger the first build

Either:

**(a)** Manual invoke from console — no bootstrap push needed since the
FROM chain is 100% public NGC.

**(b)** Push any commit to the watched branch if GitHub webhook is wired.

---

## Wiring CodePipeline (optional)

If you want automated promotion (source → build → test), use this
minimal CloudFormation:

```yaml
Resources:
  Pipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      RoleArn: !GetAtt PipelineRole.Arn
      ArtifactStore:
        Type: S3
        Location: !Ref ArtifactBucket
      Stages:
        - Name: Source
          Actions:
            - Name: GitHubSource
              ActionTypeId:
                Category: Source
                Owner: AWS
                Provider: CodeStarSourceConnection
                Version: '1'
              Configuration:
                ConnectionArn: !Ref GitHubConnection
                FullRepositoryId: dmvevents/awsome-inference-1
                BranchName: feature/dynamo-combined-vllm-trtllm-efa
              OutputArtifacts:
                - Name: SourceOutput
        - Name: Build
          Actions:
            - Name: BuildAndScan
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: '1'
              Configuration:
                ProjectName: dynamo-inference
              InputArtifacts: [{ Name: SourceOutput }]
              OutputArtifacts: [{ Name: BuildOutput }]
```

---

## Troubleshooting

### "Cannot connect to the Docker daemon"

Set `PrivilegedMode: true` on the CodeBuild project.

### "no space left on device" during combined export

You're on `BUILD_GENERAL1_LARGE`. Upgrade to `BUILD_GENERAL1_2XLARGE`.
The combined image is 48 GB.

### Networking build hangs on "network: dial tcp: lookup nvcr.io: i/o timeout"

CodeBuild VPC config is missing a NAT gateway or VPC endpoint. Either
run the project in the CodeBuild-managed network (no VPC config) or add
an S3 / ECR VPC endpoint + NAT gateway. The networking stage needs to
reach `github.com`, `efa-installer.amazonaws.com`, `nvcr.io`, and
`pypi.org`.

### CVE gate fails on a known false-positive

Set `CVE_ALLOW_CRITICAL=1` on the project for a temporary override. For
permanent suppression, add an `.trivyignore` at repo root with one
CVE-ID per line.

### Build takes longer than expected

Cold build = 45 min. Verify BuildKit `--cache-from` is pulling the
previous `:latest`. Logs should show "CACHED" on the networking stages
for warm builds. If not, check the ECR auth happened in `pre_build`.

---

## Referenced files (paths relative to 2.projects/dynamo-inference/)

- `Dockerfile.efa` — self-contained (public FROM: cuda-dl-base).
- `Dockerfile.dynamo-combined-efa` — self-contained (public FROMs: cuda-dl-base + ai-dynamo/{trtllm,vllm}-runtime).
- `Dockerfile.overlay` — reference for the overlay pattern, no SBOM stage.
- `build.sh` — orchestrates the above; `--networking-base` flag is deprecated (accepted but unused).
- `buildspec.yml` — single CodeBuild project.
- `sbom/CVE-SUMMARY.md` — last-known-good CVE ground truth.
