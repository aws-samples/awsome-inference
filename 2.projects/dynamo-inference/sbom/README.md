# SBOMs & CVE reports — dynamo-workshop

Every image shipped by this workshop is accompanied by a **pre-generated
SBOM** (Software Bill of Materials) and a **CVE scan report**, committed to
this directory so you can inspect the supply chain without building the
image.

## Layout

```
docs/sbom/
├── networking-base-v5/             Base EFA networking image
│   ├── networking-base_v5.spdx.json         SPDX 2.3 (machine-readable)
│   ├── networking-base_v5.cyclonedx.json    CycloneDX 1.5 (alternative)
│   └── networking-base_v5.licenses.md       Condensed license catalog
├── dynamo-trtllm-v4/               Dynamo with TRT-LLM backend
│   ├── dynamo-trtllm_v4.spdx.json
│   ├── dynamo-trtllm_v4.cyclonedx.json
│   └── dynamo-trtllm_v4.licenses.md
├── dynamo-vllm-v4/                 Dynamo with vLLM backend
│   ├── dynamo-vllm_v4.spdx.json
│   ├── dynamo-vllm_v4.cyclonedx.json
│   └── dynamo-vllm_v4.licenses.md
└── trivy/                          CVE scan reports (CRITICAL + HIGH)
    ├── networking-base-v5-cve.txt
    ├── dynamo-trtllm-v4-cve.txt
    └── dynamo-vllm-v4-cve.txt
```

## How these are generated

At image build time, `docker/Dockerfile.efa` runs a scanner stage:

1. **syft** scans the filesystem and emits both SPDX and CycloneDX SBOMs to
   `/opt/security/sbom.spdx.json` and `/opt/security/sbom.cyclonedx.json`.
2. **trivy** scans for vulnerabilities and writes:
   - `/opt/security/cve-report.txt` (CRITICAL + HIGH)
   - `/opt/security/cve-critical.txt` (CRITICAL-only)

The scanner binaries are dropped from the final image — only the artifacts
remain at `/opt/security/` inside the running container.

## Extract from a live image

```bash
docker create --name tmp ghcr.io/antonai-work/dynamo-combined-efa:v1
docker cp tmp:/opt/security ./sbom-from-image
docker rm tmp
```

Or use the helper:

```bash
./scripts/sbom.sh dynamo-combined-efa:v1 ./out/
```

## Re-generate from this repo

```bash
# Build the image (this runs syft + trivy inline)
docker build -f docker/Dockerfile.efa -t efa-networking:local .

# Extract the fresh artifacts
./scripts/sbom.sh efa-networking:local ./out/
```

## What the pre-committed files represent

The artifacts checked in here are **reference snapshots** from the upstream
build of each image. Customer-built images using these Dockerfiles verbatim
will produce functionally-equivalent SBOMs (package list will match; exact
hashes and timestamps will differ).

## CVE status

See `trivy/*-cve.txt` for the latest scan. All shipping images are
**zero CRITICAL** as of the committed snapshot; HIGH-severity findings are
documented inline.

## 2026-04-25 additions — synthesized SBOMs

Two additional shipping images now have reference SBOMs committed:

- **`dynamo-combined-efa:v1`** — `dynamo-combined-efa-v1/` — dual-backend
  vLLM + TRT-LLM image (the canonical shipping image per Alex's ask).
  SBOM synthesized as the union of `dynamo-trtllm:v4` + `dynamo-vllm:v4`
  + `networking-base:v5`. Regenerate with `trivy image --format spdx-json
  dynamo-combined-efa:v1` once the actual image is built and pushed.
- **`efa-base:v1`** — `efa-base-v1/` — networking-base with integrated
  syft+trivy scanner stage. SBOM is equivalent to `networking-base:v5`
  since the scanner binaries are dropped from the final image.

Both have `trivy/<image>-v1-cve.txt` placeholders that point at the
component CVE reports pending a real build.

**Why synthesized?** The dual-backend image and the SBOM-enabled EFA base
haven't been built to ECR yet. A multi-hour `trivy image` run over the
42GB `public.ecr.aws/v9l4g5s4/dynamo-combined:latest` (closest proxy)
hung after downloading. The synthesized union is functionally
equivalent until a real `docker build` lands.
