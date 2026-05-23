#!/usr/bin/env bash
# dynamo-combined-efa backend selector
#
# DYNAMO_BACKEND=vllm   -> use the base vLLM runtime env (default)
# DYNAMO_BACKEND=trtllm -> switch PYTHONPATH/PATH to the /opt/trtllm overlay
#
# If DYNAMO_BACKEND is unset or unknown, default to vllm and log a warning.
set -euo pipefail

BACKEND="${DYNAMO_BACKEND:-vllm}"

case "$BACKEND" in
  vllm)
    # vLLM is the image's native Python environment. Nothing to remap.
    exec "$@"
    ;;
  trtllm)
    # TRT-LLM ships as a self-contained venv at /opt/trtllm-venv. Activate it
    # wholesale so its Python, tensorrt_llm, trtllm-serve, etc. all match the
    # versions that NVIDIA ships together.
    if [[ ! -x /opt/trtllm-venv/bin/python3 ]]; then
      echo "[entrypoint] ERROR: /opt/trtllm-venv/bin/python3 missing — image built incorrectly" >&2
      exit 2
    fi
    export VIRTUAL_ENV="/opt/trtllm-venv"
    export PATH="/opt/trtllm-venv/bin:${PATH}"
    # TRT-LLM's torch links Intel MKL (libmkl_intel_lp64.so.1) + OpenMPI
    # (libmpi.so.40). /opt/trtllm-libs has MKL copied from the upstream
    # tensorrtllm-runtime; libmpi is provided by the distro libopenmpi3 in
    # /usr/lib/x86_64-linux-gnu. Also add trtllm's own libs dir.
    export LD_LIBRARY_PATH="/opt/trtllm-cuda13:/opt/trtllm-cuda13/nvshmem:/opt/trtllm-libs:/opt/trtllm-venv/lib/python3.12/site-packages/tensorrt_llm/libs:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    # Drop any vLLM-venv PYTHONPATH leakage.
    unset PYTHONHOME
    exec "$@"
    ;;
  help|--help|-h|"")
    cat <<'HLP'
dynamo-combined-efa — runs NVIDIA Dynamo with either TRT-LLM or vLLM over EFA.

Usage:
  docker run ... -e DYNAMO_BACKEND=vllm   dynamo-combined-efa:v1 <cmd>
  docker run ... -e DYNAMO_BACKEND=trtllm dynamo-combined-efa:v1 <cmd>

Defaults to DYNAMO_BACKEND=vllm if unset.
HLP
    [[ "$BACKEND" == "" ]] && exit 0 || exit 0
    ;;
  *)
    echo "[entrypoint] ERROR: unknown DYNAMO_BACKEND='$BACKEND' (expected: vllm | trtllm)" >&2
    exit 2
    ;;
esac
