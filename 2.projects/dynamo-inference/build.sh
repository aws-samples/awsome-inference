#!/bin/bash
#
# Dynamo Inference on AWS - Build Script
# Build EFA-enabled Docker images for NVIDIA Dynamo inference on AWS
#
# Per Alex Iankoulski's 2026-05-04 feedback:
#   - Image names: efa, dynamo-efa (no GPU suffix). One image, one name.
#   - --image-name NAME overrides the built image name (efa or combined only).
#   - --base-image URI lets the combined build consume a pre-built efa base
#     from ECR instead of rebuilding — shaves ~25 min off CodeBuild runs.
#   - Default is a fat image covering A100 → B300 + L40S (sm_80 sm_86 sm_89
#     sm_90 sm_100 sm_120).
#
# Per Alex Iankoulski's 2026-05-07 feedback (#72):
#   - Restore -a/--arch so operators can produce a targeted single-arch or
#     arch-subset image while keeping the fat default for ./build.sh (no flag).
#     Accepts a quoted space-separated sm list, e.g.:
#       ./build.sh -a "sm_90"              # H100 only
#       ./build.sh -a "sm_90 sm_100"       # H100 + H200/B200
#     The env var CUDA_ARCH_LIST="sm_90" ./build.sh is an equivalent fallback.
#

set -e

# Default values
REGISTRY=""
TAG="latest"
BUILD_TARGET="all"
PUSH=false
NO_CACHE=false
# CUDA_ARCH_LIST: space-separated sm_* tokens (e.g. "sm_90" or "sm_90 sm_100").
# Empty means "use the Dockerfile fat default" — do NOT hardcode the fat list
# here; the Dockerfiles are the single source of truth for the default so this
# script stays passive when no flag or env var is set.
CUDA_ARCH_LIST="${CUDA_ARCH_LIST:-}"
GENERATE_SBOM=1
CVE_SCAN=1
SBOM_OUT_DIR="$(pwd)/out/sbom"
EXTRACT_SBOM=1
IMAGE_NAME_OVERRIDE=""
BASE_IMAGE_OVERRIDE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build EFA-enabled Docker images for Dynamo inference on AWS."
    echo "Default is a fat binary covering sm_80 (A100), sm_86 (A10), sm_89"
    echo "(L40S/L4), sm_90 (H100), sm_100 (H200/B200), and sm_120 (B300)."
    echo "No per-GPU suffixes."
    echo ""
    echo "Options:"
    echo "  -r, --registry REGISTRY   Container registry (e.g., 123.dkr.ecr.us-east-2.amazonaws.com)"
    echo "  -t, --tag TAG             Image tag (default: latest)"
    echo "  -b, --build TARGET        Build target: efa, trtllm, vllm, combined, all (default: all)"
    echo "  -i, --image-name NAME     Override the built image name (only for -b efa or -b combined)"
    echo "      --base-image URI      Use a pre-built EFA base image (URI with tag). Only valid for"
    echo "                            -b combined / -b trtllm / -b vllm. When provided, the combined"
    echo "                            build skips the local efa dep check and passes --build-arg"
    echo "                            BASE_IMAGE=<URI> to the downstream Dockerfile."
    echo "  -a, --arch \"<sm list>\"    Build a targeted image for the given space-separated sm tokens."
    echo "                            Omit for the fat default. Equivalent to CUDA_ARCH_LIST env var."
    echo "                            Examples: \"sm_90\"  |  \"sm_90 sm_100\"  |  \"sm_80 sm_90\""
    echo "  -p, --push                Push images to registry after build"
    echo "  -n, --no-cache            Build without Docker cache"
    echo "      --no-sbom             Disable SBOM generation (default: enabled)"
    echo "      --no-cve              Disable CVE scan (default: enabled)"
    echo "      --no-extract          Skip post-build SBOM extraction to out/sbom/"
    echo "      --sbom-out DIR        Output dir for extracted SBOMs (default: ./out/sbom)"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -b efa -t v1.0.0                                   # fat efa:v1.0.0"
    echo "  $0 -b combined -t v1.0.0 \\"
    echo "     --base-image 123.dkr.ecr.us-east-2.amazonaws.com/efa:v1.0.0"
    echo "                                                         # fat dynamo-efa:v1.0.0 from ECR base"
    echo "  $0 -b efa -i my-efa-dev -t local                      # fat my-efa-dev:local"
    echo "  $0 -b combined -a \"sm_90\"                             # H100-only image"
    echo "  $0 -b combined -a \"sm_90 sm_100\"                      # H100 + H200/B200 image"
    echo "  CUDA_ARCH_LIST=\"sm_90\" $0 -b combined                 # same as -a \"sm_90\""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_TARGET="$2"
            shift 2
            ;;
        -i|--image-name)
            IMAGE_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --base-image)
            BASE_IMAGE_OVERRIDE="$2"
            shift 2
            ;;
        -a|--arch)
            CUDA_ARCH_LIST="$2"
            shift 2
            ;;
        -p|--push)
            PUSH=true
            shift
            ;;
        -n|--no-cache)
            NO_CACHE=true
            shift
            ;;
        --no-sbom) GENERATE_SBOM=0; shift ;;
        --no-cve) CVE_SCAN=0; shift ;;
        --no-extract) EXTRACT_SBOM=0; shift ;;
        --sbom-out) SBOM_OUT_DIR="$2"; shift 2 ;;
        --networking-base)
            # DEPRECATED: inlined networking stack, no private base needed.
            log_warn "--networking-base is deprecated (ignored). Dockerfiles build networking stack inline."
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Translate -a/--arch (or CUDA_ARCH_LIST env var) into NVCC_GENCODE build args.
# When empty we pass nothing and the Dockerfile's ARG NVCC_GENCODE default
# (fat list) is used. Each token must look like sm_NN; we reject anything else
# so typos don't silently yield a no-op fat build.
# NVCC_GENCODE_ARGS is an array so the value — which contains spaces — is
# passed to `docker build` as exactly one --build-arg pair.
NVCC_GENCODE_ARGS=()
if [ -n "$CUDA_ARCH_LIST" ]; then
    _gen=""
    for tok in $CUDA_ARCH_LIST; do
        if [[ ! "$tok" =~ ^sm_[0-9]+$ ]]; then
            log_error "Invalid arch token '${tok}' in -a/CUDA_ARCH_LIST. Expected sm_NN (e.g. sm_90)."
            exit 1
        fi
        cc="${tok#sm_}"
        _gen="${_gen:+${_gen} }-gencode=arch=compute_${cc},code=${tok}"
    done
    NVCC_GENCODE_ARGS=(--build-arg "NVCC_GENCODE=${_gen}")
    log_info "Targeted build: CUDA_ARCH_LIST='${CUDA_ARCH_LIST}'"
    log_info "  NVCC_GENCODE=${_gen}"
else
    log_info "Fat default build: NVCC_GENCODE from Dockerfile (sm_80..sm_120)."
fi

# Set cache option
CACHE_OPT=""
if [ "$NO_CACHE" = true ]; then
    CACHE_OPT="--no-cache"
fi

# SBOM build-args. The multi-stage Dockerfiles honor GENERATE_SBOM and CVE_SCAN.
SBOM_ARGS="--build-arg GENERATE_SBOM=${GENERATE_SBOM} --build-arg CVE_SCAN=${CVE_SCAN}"
SBOM_TARGET_ARG="--target final"

extract_sbom() {
    local img="$1"
    [ "$EXTRACT_SBOM" = "1" ] || return 0
    local sub="${img//[:\/]/_}"
    mkdir -p "${SBOM_OUT_DIR}/${sub}"
    local cid
    cid=$(docker create "${img}" 2>/dev/null) || { log_warn "  extract_sbom: cannot create from ${img}"; return 0; }
    if docker cp "${cid}:/opt/security/." "${SBOM_OUT_DIR}/${sub}/" 2>/dev/null; then
        log_info "  SBOM of ${img} -> ${SBOM_OUT_DIR}/${sub}/"
    else
        log_warn "  ${img} has no /opt/security dir"
    fi
    docker rm "${cid}" >/dev/null 2>&1 || true
}

# Default image names (Alex 2026-05-04: no GPU suffixes; flat names).
EFA_IMAGE="efa"
TRTLLM_IMAGE="dynamo-trtllm-efa"
VLLM_IMAGE="dynamo-vllm-efa"
COMBINED_IMAGE="dynamo-efa"

# --image-name override semantics:
#   -b efa       → sets EFA_IMAGE
#   -b combined  → sets COMBINED_IMAGE
#   -b all       → reject (ambiguous which image to rename)
#   -b trtllm/vllm → reject for now (not in Alex's ask; open question)
if [ -n "$IMAGE_NAME_OVERRIDE" ]; then
    case $BUILD_TARGET in
        efa)
            EFA_IMAGE="$IMAGE_NAME_OVERRIDE"
            ;;
        combined)
            COMBINED_IMAGE="$IMAGE_NAME_OVERRIDE"
            ;;
        all|trtllm|vllm)
            log_error "--image-name is only valid for -b efa or -b combined, not ${BUILD_TARGET}"
            exit 1
            ;;
    esac
fi

# --base-image only valid for downstream builds (combined/trtllm/vllm)
if [ -n "$BASE_IMAGE_OVERRIDE" ]; then
    case $BUILD_TARGET in
        combined|trtllm|vllm)
            log_info "Using pre-built base image: ${BASE_IMAGE_OVERRIDE}"
            ;;
        efa|all)
            log_error "--base-image is only valid for -b combined / -b trtllm / -b vllm"
            exit 1
            ;;
    esac
fi

build_efa() {
    local IMAGE_NAME="${EFA_IMAGE}"
    log_info "Building base EFA image: ${IMAGE_NAME}:${TAG}"

    docker build ${CACHE_OPT} ${SBOM_ARGS} ${SBOM_TARGET_ARG} "${NVCC_GENCODE_ARGS[@]}" \
        -f Dockerfile.efa \
        -t ${IMAGE_NAME}:${TAG} \
        .

    if [ -n "$REGISTRY" ]; then
        docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}
        log_info "Tagged: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    fi

    extract_sbom "${IMAGE_NAME}:${TAG}"
}

# Resolve the BASE_IMAGE that downstream Dockerfiles should use.
# Precedence: --base-image > ${EFA_IMAGE}:${TAG} local.
_resolve_base_image() {
    if [ -n "$BASE_IMAGE_OVERRIDE" ]; then
        echo "$BASE_IMAGE_OVERRIDE"
    else
        echo "${EFA_IMAGE}:${TAG}"
    fi
}

# Ensure base is present. If --base-image was given, trust it. Otherwise
# build the local efa image if it's not already cached.
_ensure_base() {
    if [ -n "$BASE_IMAGE_OVERRIDE" ]; then
        log_info "Skipping local efa build; --base-image ${BASE_IMAGE_OVERRIDE} provided."
        return 0
    fi
    if ! docker image inspect ${EFA_IMAGE}:${TAG} > /dev/null 2>&1; then
        log_warn "Base EFA image not found locally, building it first..."
        build_efa
    fi
}

build_trtllm() {
    local IMAGE_NAME="${TRTLLM_IMAGE}"
    local BASE_REF
    _ensure_base
    BASE_REF="$(_resolve_base_image)"
    log_info "Building TensorRT-LLM image: ${IMAGE_NAME}:${TAG} (base=${BASE_REF})"

    docker build ${CACHE_OPT} ${SBOM_ARGS} ${SBOM_TARGET_ARG} \
        -f Dockerfile.dynamo-trtllm-efa \
        --build-arg BASE_IMAGE=${BASE_REF} \
        -t ${IMAGE_NAME}:${TAG} \
        .

    if [ -n "$REGISTRY" ]; then
        docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}
        log_info "Tagged: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    fi

    extract_sbom "${IMAGE_NAME}:${TAG}"
}

build_vllm() {
    local IMAGE_NAME="${VLLM_IMAGE}"
    local BASE_REF
    _ensure_base
    BASE_REF="$(_resolve_base_image)"
    log_info "Building vLLM image: ${IMAGE_NAME}:${TAG} (base=${BASE_REF})"

    docker build ${CACHE_OPT} ${SBOM_ARGS} ${SBOM_TARGET_ARG} \
        -f Dockerfile.dynamo-vllm-efa \
        --build-arg BASE_IMAGE=${BASE_REF} \
        -t ${IMAGE_NAME}:${TAG} \
        .

    if [ -n "$REGISTRY" ]; then
        docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}
        log_info "Tagged: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    fi

    extract_sbom "${IMAGE_NAME}:${TAG}"
}

build_combined() {
    local IMAGE_NAME="${COMBINED_IMAGE}"
    local BASE_REF
    _ensure_base
    BASE_REF="$(_resolve_base_image)"
    log_info "Building combined (vLLM + TRT-LLM) image: ${IMAGE_NAME}:${TAG} (base=${BASE_REF})"

    docker build ${CACHE_OPT} ${SBOM_ARGS} ${SBOM_TARGET_ARG} "${NVCC_GENCODE_ARGS[@]}" \
        -f Dockerfile.dynamo-combined-efa \
        --build-arg BASE_IMAGE=${BASE_REF} \
        -t ${IMAGE_NAME}:${TAG} \
        .

    if [ -n "$REGISTRY" ]; then
        docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}
        log_info "Tagged: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    fi

    extract_sbom "${IMAGE_NAME}:${TAG}"
}

# Function to check if ECR repository exists and create if needed
create_ecr_repo() {
    local repo_name=$1
    local registry_alias=""

    # Determine if it's public or private ECR
    if [[ "$REGISTRY" == *"public.ecr.aws"* ]]; then
        # Public ECR
        registry_alias=$(echo $REGISTRY | cut -d'/' -f2)

        # Check if repository exists
        if ! aws ecr-public describe-repositories --registry-id $registry_alias --repository-names $repo_name --region us-east-1 >/dev/null 2>&1; then
            log_info "Creating public ECR repository: $repo_name"
            aws ecr-public create-repository \
                --repository-name $repo_name \
                --registry-id $registry_alias \
                --region us-east-1 \
                --no-cli-pager 2>/dev/null || true
        else
            log_info "Repository $repo_name already exists"
        fi
    elif [[ "$REGISTRY" == *"dkr.ecr"* ]]; then
        # Private ECR
        local region=$(echo $REGISTRY | cut -d'.' -f4)

        # Check if repository exists
        if ! aws ecr describe-repositories --repository-names $repo_name --region $region >/dev/null 2>&1; then
            log_info "Creating private ECR repository: $repo_name"
            aws ecr create-repository \
                --repository-name $repo_name \
                --region $region \
                --image-scanning-configuration scanOnPush=true \
                --no-cli-pager 2>/dev/null || true
        else
            log_info "Repository $repo_name already exists"
        fi
    fi
}

# Function to authenticate with ECR
ecr_login() {
    if [[ "$REGISTRY" == *"public.ecr.aws"* ]]; then
        # Public ECR login
        log_info "Authenticating with public ECR..."
        aws ecr-public get-login-password --region us-east-1 | \
            docker login --username AWS --password-stdin $REGISTRY 2>/dev/null
    elif [[ "$REGISTRY" == *"dkr.ecr"* ]]; then
        # Private ECR login
        local region=$(echo $REGISTRY | cut -d'.' -f4)
        local account=$(echo $REGISTRY | cut -d'.' -f1)
        log_info "Authenticating with private ECR in $region..."
        aws ecr get-login-password --region $region | \
            docker login --username AWS --password-stdin $REGISTRY 2>/dev/null
    else
        log_warn "Registry is not AWS ECR, skipping automatic authentication"
    fi
}

push_images() {
    if [ -z "$REGISTRY" ]; then
        log_error "Registry not specified. Use -r or --registry option."
        exit 1
    fi

    # Authenticate with ECR if needed
    ecr_login

    # Create repositories if they don't exist
    case $BUILD_TARGET in
        efa)
            create_ecr_repo ${EFA_IMAGE}
            ;;
        trtllm)
            create_ecr_repo ${TRTLLM_IMAGE}
            ;;
        vllm)
            create_ecr_repo ${VLLM_IMAGE}
            ;;
        combined)
            create_ecr_repo ${COMBINED_IMAGE}
            ;;
        all)
            create_ecr_repo ${EFA_IMAGE}
            create_ecr_repo ${TRTLLM_IMAGE}
            create_ecr_repo ${VLLM_IMAGE}
            create_ecr_repo ${COMBINED_IMAGE}
            ;;
    esac

    log_info "Pushing images to ${REGISTRY}..."

    case $BUILD_TARGET in
        efa)
            docker push ${REGISTRY}/${EFA_IMAGE}:${TAG} || log_error "Failed to push ${EFA_IMAGE}"
            log_info "Pushed: ${REGISTRY}/${EFA_IMAGE}:${TAG}"
            ;;
        trtllm)
            docker push ${REGISTRY}/${TRTLLM_IMAGE}:${TAG} || log_error "Failed to push ${TRTLLM_IMAGE}"
            log_info "Pushed: ${REGISTRY}/${TRTLLM_IMAGE}:${TAG}"
            ;;
        vllm)
            docker push ${REGISTRY}/${VLLM_IMAGE}:${TAG} || log_error "Failed to push ${VLLM_IMAGE}"
            log_info "Pushed: ${REGISTRY}/${VLLM_IMAGE}:${TAG}"
            ;;
        combined)
            docker push ${REGISTRY}/${COMBINED_IMAGE}:${TAG} || log_error "Failed to push ${COMBINED_IMAGE}"
            log_info "Pushed: ${REGISTRY}/${COMBINED_IMAGE}:${TAG}"
            ;;
        all)
            docker push ${REGISTRY}/${EFA_IMAGE}:${TAG}        || log_error "Failed to push ${EFA_IMAGE}"
            docker push ${REGISTRY}/${TRTLLM_IMAGE}:${TAG}     || log_error "Failed to push ${TRTLLM_IMAGE}"
            docker push ${REGISTRY}/${VLLM_IMAGE}:${TAG}       || log_error "Failed to push ${VLLM_IMAGE}"
            docker push ${REGISTRY}/${COMBINED_IMAGE}:${TAG}   || log_error "Failed to push ${COMBINED_IMAGE}"
            log_info "Pushed: all images to ${REGISTRY} at ${TAG}"
            ;;
    esac

    log_info "Push completed successfully!"
}

# Function to check prerequisites
check_prerequisites() {
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check if AWS CLI is installed when pushing to ECR
    if [ "$PUSH" = true ] && [ -n "$REGISTRY" ]; then
        if [[ "$REGISTRY" == *"ecr.aws"* ]]; then
            if ! command -v aws &> /dev/null; then
                log_error "AWS CLI is not installed. Please install AWS CLI to push to ECR."
                exit 1
            fi

            # Check AWS credentials
            if ! aws sts get-caller-identity &> /dev/null; then
                log_error "AWS credentials not configured. Please run 'aws configure' or set AWS credentials."
                exit 1
            fi
        fi
    fi
}

# Main build logic
log_info "Dynamo Inference on AWS - Build Script"
log_info "Build target: ${BUILD_TARGET}"
log_info "Tag: ${TAG}"

# Check prerequisites
check_prerequisites

case $BUILD_TARGET in
    efa)
        build_efa
        ;;
    trtllm)
        build_trtllm
        ;;
    vllm)
        build_vllm
        ;;
    combined)
        build_combined
        ;;
    all)
        build_efa
        build_trtllm
        build_vllm
        build_combined
        ;;
    *)
        log_error "Invalid build target: ${BUILD_TARGET}"
        print_usage
        exit 1
        ;;
esac

if [ "$PUSH" = true ]; then
    push_images
fi

log_info "Build completed successfully!"
echo ""
echo "Built images:"
docker images | grep -E "(^${EFA_IMAGE}[[:space:]]|^${TRTLLM_IMAGE}[[:space:]]|^${VLLM_IMAGE}[[:space:]]|^${COMBINED_IMAGE}[[:space:]])" | head -10
