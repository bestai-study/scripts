#!/usr/bin/env bash
# Setup for TypeSafe's Jev System One model - Python SDK (and optional Node.js SDK).
# Installs into a dedicated venv so it never touches the system Python.
#
# Tested: ubuntu:24.04, Python 3.12, typesafe-sdk 0.7.0, Node 20.20.2,
# @typesafe-ai/sdk, September 2026.
#
# Options:
#   --node             Also provision Node.js 20 (arm64/x64) and install the JS SDK.
#   --venv <path>      venv directory (default: $HOME/typesafe-venv)
#   -h, --help         Show this help.
set -euo pipefail

VENV_DIR="${HOME}/typesafe-venv"
WITH_NODE=0

usage() { sed -n '2,12p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node) WITH_NODE=1 ;;
    --venv) VENV_DIR="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq python3 python3-venv python3-pip curl

echo "==> creating venv at $VENV_DIR"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q --upgrade pip

echo "==> installing typesafe-sdk"
"$VENV_DIR/bin/pip" install -q typesafe-sdk
"$VENV_DIR/bin/python" -c "import typesafe_sdk; print('typesafe-sdk OK:', typesafe_sdk.__version__ if hasattr(typesafe_sdk,'__version__') else 'installed')"

if [[ "$WITH_NODE" -eq 1 ]]; then
  echo "==> provisioning Node.js 20"
  if command -v node >/dev/null 2>&1 && [[ "$(node -v)" == v20.* ]]; then
    echo "node20 already present: $(node -v)"
  else
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64)  N_ARCH=x64 ;;
      aarch64) N_ARCH=arm64 ;;
      *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
    esac
    # Resolve the latest v20 patch as published by nodejs.org.
    IDX="$(curl -fsSL --retry 3 --retry-all-errors "https://nodejs.org/dist/latest-v20.x/")"
    TARBALL="$(echo "$IDX" | grep -o "node-v20[0-9.]*-linux-${N_ARCH}.tar.xz" | sort -u | tail -1)"
    [[ -z "$TARBALL" ]] && { echo "could not resolve node v20 tarball" >&2; exit 1; }
    echo "resolving: $TARBALL"
    curl -fsSL --retry 3 --retry-all-errors -o "/tmp/$TARBALL" \
      "https://nodejs.org/dist/latest-v20.x/$TARBALL"
    sudo rm -rf /opt/node20
    sudo mkdir -p /opt/node20
    sudo tar -xJf "/tmp/$TARBALL" -C /opt/node20 --strip-components=1
    echo 'export PATH="/opt/node20/bin:$PATH"' | sudo tee /etc/profile.d/node20.sh >/dev/null
  fi
  export PATH="/opt/node20/bin:$PATH"
  echo "==> installing @typesafe-ai/sdk"
  mkdir -p "$HOME/typesafe-node"
  ( cd "$HOME/typesafe-node" && npm install -q --no-fund --no-audit @typesafe-ai/sdk )
fi

echo "==> done. Set your API key and run the demo:"
echo "    export TYPESAFE_API_KEY=<your_key>   # https://console.typesafe.ai/keys"
echo "    $VENV_DIR/bin/python jev_triage.py"
[[ "$WITH_NODE" -eq 1 ]] && echo "    node demo path: $HOME/typesafe-node"