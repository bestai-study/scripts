#!/usr/bin/env bash
# One-click setup for Laya (Convai Innovations) - System 1 decision engine.
# Installs into a dedicated venv so it never touches the system Python.
#
# Follows the official install path: CPU-only PyTorch from the PyTorch index
# first (avoids the multi-GB CUDA bundles on PyPI), then `laya` from PyPI.
# Source the package docs at https://nandhakishorm.github.io/laya/ and the
# GitHub README (github.com/NandhaKishorM/laya).
#
# Tested: ubuntu:24.04, Python 3.12, laya 0.3.20, torch 2.14.0+cpu, September 2026.
#
# Options:
#   --serve            Also install laya[serve] (Jev-compatible HTTP server).
#   --preload          Download and warm the English checkpoint (~1 GB) so the
#                      first predict call does not wait for the first download.
#   --venv <path>      venv directory (default: $HOME/laya-venv)
#   --skip-verify      Skip the post-install version/CLI checks.
#   -h, --help         Show this help.
set -euo pipefail

VENV_DIR="${HOME}/laya-venv"
WITH_SERVE=0
WITH_PRELOAD=0
VERIFY=1

usage() { sed -n '2,18p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serve) WITH_SERVE=1 ;;
    --preload) WITH_PRELOAD=1 ;;
    --venv) VENV_DIR="$2"; shift ;;
    --skip-verify) VERIFY=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

# pip on this network drops big wheels mid-transfer; retry everything.
# Always install through the venv's python so the system python (PEP 668)
# never gets touched.
export PIP_DEFAULT_TIMEOUT=120
pip_install() { "$VENV_DIR/bin/python" -m pip install --retries 8 --timeout 120 "$@"; }

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq python3 python3-venv python3-pip curl

echo "==> creating venv at $VENV_DIR"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q --upgrade pip

echo "==> installing CPU-only PyTorch 2.14 from the PyTorch index"
if ! pip_install "torch==2.14.0" --index-url https://download.pytorch.org/whl/cpu; then
  echo "warning: CPU torch index unavailable; falling back to default PyPI (CUDA bundle)" >&2
  pip_install "torch==2.14.0"
fi

echo "==> installing laya"
if [[ "$WITH_SERVE" -eq 1 ]]; then
  pip_install "laya[serve]"
else
  pip_install laya
fi

if [[ "$VERIFY" -eq 1 ]]; then
  echo "==> verifying install"
  PY="$VENV_DIR/bin/python"
  "$PY" -I -c "import laya; print('laya OK, installed version:', laya.__version__)"
  "$VENV_DIR/bin/laya" "I was charged twice, please refund" >/dev/null
  echo "laya CLI OK (routing decision, offline - no weights downloaded)"
fi

if [[ "$WITH_PRELOAD" -eq 1 ]]; then
  echo "==> warming the English checkpoint (first predict downloads ~1 GB from Hugging Face)"
  "$VENV_DIR/bin/laya" "Please refund invoice 4411" --predict >/dev/null
  echo "preload OK"
fi

echo "==> installed. Quick start:"
echo "    $VENV_DIR/bin/laya 'My payment failed twice' --preset triage"
echo "    ${VENV_DIR}/bin/python -c \"from laya import load; a=load('convaiinnovations/laya'); print(a.predict('refund please', {'d': {'type':'choice','instructions':'dept?','criteria':{'billing':'refunds','other':None}}}))\""
if [[ "$WITH_SERVE" -eq 1 ]]; then
  echo "    HTTP server (Jev-compatible POST /v1/systemone):"
  echo "    LAYA_DEVICE=cpu LAYA_PRELOAD=1 $VENV_DIR/bin/laya-serve"
fi
echo "    Docs: https://nandhakishorm.github.io/laya/"
echo "    Weights auto-download from https://huggingface.co/convaiinnovations/laya on first predict."