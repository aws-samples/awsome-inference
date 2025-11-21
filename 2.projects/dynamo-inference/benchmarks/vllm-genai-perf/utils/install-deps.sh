#!/usr/bin/env bash
# Dependency Installation Script
# Installs required dependencies for the benchmark suite
set -euo pipefail

echo "Installing benchmark suite dependencies..."
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Update package lists (for apt-based systems)
if command -v apt-get &> /dev/null; then
    echo "Updating package lists..."
    $SUDO apt-get update -qq
fi

# Install system dependencies
echo "Installing system dependencies..."

# jq for JSON processing
if ! command -v jq &> /dev/null; then
    echo "  Installing jq..."
    if command -v apt-get &> /dev/null; then
        $SUDO apt-get install -y jq
    elif command -v yum &> /dev/null; then
        $SUDO yum install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    else
        echo "    WARNING: Could not install jq automatically"
    fi
else
    echo "  jq: already installed"
fi

# curl for health checks
if ! command -v curl &> /dev/null; then
    echo "  Installing curl..."
    if command -v apt-get &> /dev/null; then
        $SUDO apt-get install -y curl
    elif command -v yum &> /dev/null; then
        $SUDO yum install -y curl
    else
        echo "    WARNING: Could not install curl automatically"
    fi
else
    echo "  curl: already installed"
fi

# Python3 and pip
if ! command -v python3 &> /dev/null; then
    echo "  Installing python3..."
    if command -v apt-get &> /dev/null; then
        $SUDO apt-get install -y python3 python3-pip
    elif command -v yum &> /dev/null; then
        $SUDO yum install -y python3 python3-pip
    else
        echo "    ERROR: Could not install python3 automatically"
        exit 1
    fi
else
    echo "  python3: already installed ($(python3 --version))"
fi

# Install Python dependencies
echo ""
echo "Installing Python packages..."

# Check if pip is available
if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &> /dev/null; then
    echo "  Installing pip..."
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3
fi

# Install required Python packages
PYTHON_PACKAGES=(
    "pyyaml"
    "requests"
    "tabulate"
)

OPTIONAL_PACKAGES=(
    "pandas"
    "matplotlib"
    "seaborn"
    "jinja2"
)

for package in "${PYTHON_PACKAGES[@]}"; do
    if ! python3 -c "import ${package//-/_}" 2>/dev/null; then
        echo "  Installing $package..."
        python3 -m pip install --user "$package"
    else
        echo "  $package: already installed"
    fi
done

echo ""
echo "Installing optional Python packages for enhanced reporting..."
for package in "${OPTIONAL_PACKAGES[@]}"; do
    if ! python3 -c "import ${package//-/_}" 2>/dev/null; then
        echo "  Installing $package (optional)..."
        python3 -m pip install --user "$package" || \
            echo "    WARNING: Could not install $package"
    else
        echo "  $package: already installed"
    fi
done

# Docker
echo ""
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Docker is required for GenAI-Perf benchmarks."
    echo "Please install Docker:"
    echo "  https://docs.docker.com/engine/install/"
    echo ""
else
    echo "Docker: already installed ($(docker --version))"

    # Pull GenAI-Perf image
    echo "Pulling GenAI-Perf Docker image..."
    docker pull nvcr.io/nvidia/tritonserver:24.10-py3-sdk || \
        echo "  WARNING: Could not pull GenAI-Perf image"
fi

# kubectl (for Kubernetes deployments)
echo ""
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Installing kubectl is recommended for Kubernetes deployments."
    echo ""
    echo "To install kubectl:"
    echo "  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
    echo "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    echo ""
else
    echo "kubectl: already installed ($(kubectl version --client --short 2>/dev/null || echo 'version check failed'))"
fi

# vLLM (optional, for local testing)
echo ""
if ! python3 -c "import vllm" 2>/dev/null; then
    echo "vLLM not found (optional for local testing)."
    echo "To install vLLM:"
    echo "  pip install vllm"
    echo ""
else
    echo "vLLM: already installed ($(python3 -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo 'version unknown'))"
fi

echo ""
echo "═════════════════════════════════════════════════"
echo "Dependency installation complete!"
echo "═════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  ✓ System tools: jq, curl"
echo "  ✓ Python packages: pyyaml, requests, tabulate"
echo "  ○ Optional: pandas, matplotlib, seaborn, jinja2"
echo ""
echo "Next steps:"
echo "  1. Set up environment: source utils/setup-env.sh"
echo "  2. Run benchmarks: ./master-benchmark.sh --all"
echo ""
