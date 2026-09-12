#!/usr/bin/env bash
#
# install-codex-ubuntu24.sh
#
# Installs Codex CLI (https://developers.openai.com/codex) on
# Ubuntu 24.04 LTS (Noble).
#
# What this script does, in order:
#   1. Installs required system dependencies with apt (needs sudo).
#   2. Downloads the official Codex standalone installer
#      (curl -fsSL https://chatgpt.com/codex/install.sh) with retries.
#   3. Runs the official installer as your own user, so the binary lands in
#      ~/.local/bin/codex and your shell PATH is updated.
#
# The installer is downloaded from https://chatgpt.com/codex/install.sh.
# On networks where chatgpt.com is unreachable (restricted networks, e.g.
# mainland China), route the download through a proxy by exporting a
# standard proxy variable before running:
#   HTTPS_PROXY=http://127.0.0.1:7890 ./install-codex-ubuntu24.sh
# The proxy address above is just a placeholder - replace it with your own
# proxy, or leave the variable unset when your network does not need one.
#
# As a last resort, set CODEX_INSTALLER_URL to a reachable mirror of the
# official installer (published in the openai/codex GitHub repo at
# scripts/install/install.sh):
#   CODEX_INSTALLER_URL=https://example.com/codex-install.sh ./install-codex-ubuntu24.sh
#
# Usage:
#   ./install-codex-ubuntu24.sh
#   ./install-codex-ubuntu24.sh --version 0.154.0
#
# Options:
#   -v, --version <ver>    Install a specific Codex release version
#   -h, --help             Show this help and exit

set -euo pipefail

VERSION=""
INSTALLER_URL="${CODEX_INSTALLER_URL:-https://chatgpt.com/codex/install.sh}"
ORIG_ARGS=("$@")

# Collect standard proxy variables so they survive the sudo re-exec AND the
# user switch below (sudo resets the environment by default). If unset, the
# export line becomes a harmless no-op.
PROXY_EXPORT="true"
for proxy_var in ALL_PROXY all_proxy HTTP_PROXY http_proxy HTTPS_PROXY https_proxy; do
    if [[ -n "${!proxy_var:-}" ]]; then
        PROXY_EXPORT="export ${proxy_var}=${!proxy_var}"
        break
    fi
done

usage() {
    sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -v|--version)
            VERSION="${2:-}"
            if [[ -z "$VERSION" ]]; then
                echo "Error: --version requires a version argument" >&2
                exit 1
            fi
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Step 0: escalate to root if we are not already running as root.
# ---------------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "Error: sudo is required but not installed." >&2
        exit 1
    fi
    echo "Requesting sudo to install system dependencies..."
    exec sudo -E bash "$0" "${ORIG_ARGS[@]}"
fi

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="/home/${REAL_USER}"
if [[ "$REAL_USER" == "root" ]]; then
    REAL_HOME="/root"
fi

mkdir -p "$REAL_HOME"
chown "$REAL_USER":"$REAL_USER" "$REAL_HOME" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 1: system dependencies via apt.
# ---------------------------------------------------------------------------
INSTALL_INSTALLER_DEPS=(curl git tar gzip ca-certificates)

echo "==> Updating package lists..."
DEBIAN_FRONTEND=noninteractive apt-get update -y

echo "==> Installing required packages: ${INSTALL_INSTALLER_DEPS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${INSTALL_INSTALLER_DEPS[@]}"

# ---------------------------------------------------------------------------
# Step 2: download the official Codex installer as the real user.
# The CDN serving chatgpt.com/codex/install.sh occasionally resets the
# connection mid-transfer, so curl is given its own retry settings.
# ---------------------------------------------------------------------------
INSTALLER_TMP="${TMPDIR:-/tmp}/codex-install-pid$$"
mkdir -p "$INSTALLER_TMP"
chown "$REAL_USER":"$REAL_USER" "$INSTALLER_TMP"

fetch() {
    local url="$1"
    local dest="$2"
    MAX_CURL_ATTEMPTS=${MAX_CURL_ATTEMPTS:-8}
    for attempt in $(seq 1 "$MAX_CURL_ATTEMPTS"); do
        echo "    Fetching $dest (attempt $attempt/$MAX_CURL_ATTEMPTS)..."
        if curl -4 -fSL --connect-timeout 20 --retry 3 --retry-delay 3 \
              --retry-all-errors -o "$dest" "$url" 2>"$INSTALLER_TMP/curl.err"; then
            echo "    Fetched $dest ($(wc -c < "$dest") bytes)."
            return 0
        fi
        sleep 4
    done
    echo "Error: failed to download $url after $MAX_CURL_ATTEMPTS attempts" >&2
    tail -3 "$INSTALLER_TMP/curl.err" >&2 2>/dev/null || true
    return 1
}

echo "==> Downloading the official Codex installer (as $REAL_USER)..."
sudo -H -u "$REAL_USER" -- bash -c "
    $PROXY_EXPORT
    INSTALLER_TMP='$INSTALLER_TMP'
    INSTALLER_URL='$INSTALLER_URL'
    $(declare -f fetch)
    mkdir -p \"\$INSTALLER_TMP\"
    fetch \"\$INSTALLER_URL\" \"\$INSTALLER_TMP/install.sh\" || exit 1
"

# ---------------------------------------------------------------------------
# Step 3: run the official Codex installer.
# The installer checksum-verifies the release it downloads (from
# releases.openai.com, with a GitHub Releases fallback) and writes to
# ~/.local/bin plus your shell rc file, so it must run as the real user.
# ---------------------------------------------------------------------------
CODEX_CMD="CODEX_NON_INTERACTIVE=1 bash '$INSTALLER_TMP/install.sh'"
if [[ -n "$VERSION" ]]; then
    CODEX_CMD+=" --release $VERSION"
fi

echo "==> Running the official Codex installer (as $REAL_USER)..."
sudo -H -u "$REAL_USER" -- bash -c "$PROXY_EXPORT
$CODEX_CMD"

rm -rf "$INSTALLER_TMP"

# ---------------------------------------------------------------------------
# Step 4: verify the installation.
# ---------------------------------------------------------------------------
INSTALLED_BIN="${REAL_HOME}/.local/bin/codex"
if [[ -x "$INSTALLED_BIN" ]]; then
    echo "==> Codex installed successfully:"
    sudo -H -u "$REAL_USER" -- "$INSTALLED_BIN" --version
else
    echo "Error: codex binary not found at $INSTALLED_BIN" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 5: post-install hints.
# ---------------------------------------------------------------------------
cat <<EOF

Codex is ready. Next steps:

  1. Open a new terminal (so PATH picks up ~/.local/bin), or run:
        source ~/.bashrc

  2. Sign in (run from a project directory):
        cd your-project && codex
        Then choose "Sign in with ChatGPT" (or use an OPENAI_API_KEY).

  3. More details: https://developers.openai.com/codex
EOF