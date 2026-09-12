#!/usr/bin/env bash
#
# install-claude-code-ubuntu24.sh
#
# Installs Claude Code (https://code.claude.com) on Ubuntu 24.04 LTS (Noble)
# from Anthropic's official signed apt repository.
#
# What this script does, in order:
#   1. Installs required system dependencies with apt: curl and gnupg.
#   2. Downloads Anthropic's Claude Code signing key and verifies its
#      fingerprint against the published value before trusting it.
#   3. Registers the official apt repository (stable channel by default).
#   4. Installs the claude-code package with apt.
#
# The key and the apt repository live on downloads.claude.ai. On networks
# where that host is unreachable (restricted networks, e.g. mainland China),
# route the download through a proxy by exporting a standard proxy variable
# before running:
#   HTTPS_PROXY=http://127.0.0.1:7890 ./install-claude-code-ubuntu24.sh
# The proxy address above is just a placeholder - replace it with your own
# proxy, or leave the variable unset when your network does not need one.
#
# Usage:
#   ./install-claude-code-ubuntu24.sh
#   ./install-claude-code-ubuntu24.sh --channel latest
#
# Options:
#   -c, --channel <name>   apt channel: stable (default) or latest
#   -h, --help             Show this help and exit

set -euo pipefail

CHANNEL="stable"
EXPECTED_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
ORIG_ARGS=("$@")

# Collect standard proxy variables so they survive the sudo re-exec below
# (sudo resets the environment by default). If unset, PROXY_EXPORT becomes
# a harmless no-op line.
PROXY_EXPORT="true"
for proxy_var in ALL_PROXY all_proxy HTTP_PROXY http_proxy HTTPS_PROXY https_proxy; do
    if [[ -n "${!proxy_var:-}" ]]; then
        PROXY_EXPORT="export ${proxy_var}=${!proxy_var}"
        break
    fi
done

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -c|--channel)
            CHANNEL="${2:-}"
            if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "latest" ]]; then
                echo "Error: --channel must be 'stable' or 'latest'" >&2
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

# Carry the proxy variables (if any) into this root process; no-op otherwise.
$PROXY_EXPORT

# ---------------------------------------------------------------------------
# Step 1: system dependencies via apt.
# ---------------------------------------------------------------------------
INSTALL_INSTALLER_DEPS=(curl ca-certificates gnupg)

echo "==> Updating package lists..."
DEBIAN_FRONTEND=noninteractive apt-get update -y

echo "==> Installing required packages: ${INSTALL_INSTALLER_DEPS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${INSTALL_INSTALLER_DEPS[@]}"

# ---------------------------------------------------------------------------
# Step 2: download and verify Anthropic's signing key.
# docs reference: fingerprint 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
# ---------------------------------------------------------------------------
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="${KEYRING_DIR}/claude-code.asc"

echo "==> Downloading the Claude Code signing key..."
install -d -m 0755 "$KEYRING_DIR"

fetch() {
    local url="$1"
    local dest="$2"
    MAX_CURL_ATTEMPTS=${MAX_CURL_ATTEMPTS:-8}
    for attempt in $(seq 1 "$MAX_CURL_ATTEMPTS"); do
        echo "    Fetching $dest (attempt $attempt/$MAX_CURL_ATTEMPTS)..."
        if curl -fSL --connect-timeout 20 --retry 3 --retry-delay 3 \
              --retry-all-errors -o "$dest" "$url"; then
            echo "    Fetched $dest ($(wc -c < "$dest") bytes)."
            return 0
        fi
        sleep 4
    done
    echo "Error: failed to download $url after $MAX_CURL_ATTEMPTS attempts" >&2
    return 1
}

fetch "https://downloads.claude.ai/keys/claude-code.asc" "$KEYRING_FILE"

FINGERPRINT="$(gpg --show-keys --with-colons "$KEYRING_FILE" 2>/dev/null \
    | awk -F: '/^fpr:/{print $10; exit; }' || true)"
if [[ -z "$FINGERPRINT" ]]; then
    echo "Error: could not read a fingerprint from $KEYRING_FILE" >&2
    exit 1
fi

if [[ "$FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]]; then
    echo "Error: signing key fingerprint mismatch." >&2
    echo "    Expected: $EXPECTED_FINGERPRINT" >&2
    echo "    Got:      $FINGERPRINT" >&2
    echo "    Refusing to register the repository." >&2
    exit 1
fi
echo "==> Signing key verified: $FINGERPRINT (Anthropic Claude Code)"

# ---------------------------------------------------------------------------
# Step 3: register the official apt repository.
# ---------------------------------------------------------------------------
REPO_BASE="https://downloads.claude.ai/claude-code/apt"
echo "deb [signed-by=${KEYRING_FILE}] ${REPO_BASE}/${CHANNEL} ${CHANNEL} main" \
    > /etc/apt/sources.list.d/claude-code.list

echo "==> Repository registered (channel: $CHANNEL):"
cat /etc/apt/sources.list.d/claude-code.list

# ---------------------------------------------------------------------------
# Step 4: install the claude-code package.
# ---------------------------------------------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    claude-code

# ---------------------------------------------------------------------------
# Step 5: verify the installation.
# ---------------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
    echo "==> Claude Code installed successfully:"
    claude --version
else
    echo "Error: claude binary not found after install" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 6: post-install hints.
# ---------------------------------------------------------------------------
cat <<EOF

Claude Code is ready. Next steps:

  1. Authenticate from a project directory (browser sign-in):
        cd your-project && claude

  2. Or set an ANTHROPIC_API_KEY in your shell, and Claude Code will
        prompt you to approve using it.

  3. Upgrade later with:
        sudo apt update && sudo apt upgrade claude-code

  More details: https://code.claude.com/docs
EOF