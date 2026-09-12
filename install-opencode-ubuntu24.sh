#!/usr/bin/env bash
#
# install-opencode-ubuntu24.sh
#
# Installs OpenCode (https://opencode.ai) on Ubuntu 24.04 LTS (Noble).
#
# What this script does, in order:
#   1. Installs required system dependencies with apt (needs sudo).
#   2. Optionally installs a modern terminal emulator (kitty), per the
#      OpenCode docs' prerequisite list. Disable with --skip-terminal.
#   3. Runs the official OpenCode installer
#      (curl -fsSL https://opencode.ai/install | bash) as your own user,
#      so the binary lands in ~/.opencode/bin and your shell PATH is updated.
#
# Usage:
#   ./install-opencode-ubuntu24.sh
#   ./install-opencode-ubuntu24.sh --skip-terminal
#   ./install-opencode-ubuntu24.sh --version 1.0.180
#
# Options:
#   -v, --version <ver>    Install a specific OpenCode release version
#   -s, --skip-terminal    Do not install the optional terminal emulator
#       --no-modify-path   Do not modify shell rc files (PATH setup)
#   -h, --help             Show this help and exit

set -euo pipefail

VERSION=""
SKIP_TERMINAL=false
NO_MODIFY_PATH=false
ORIG_ARGS=("$@")

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
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
        -s|--skip-terminal)
            SKIP_TERMINAL=true
            shift
            ;;
        --no-modify-path)
            NO_MODIFY_PATH=true
            shift
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
INSTALL_INSTALLER_DEPS=(curl git tar gzip unzip ca-certificates)

echo "==> Updating package lists..."
DEBIAN_FRONTEND=noninteractive apt-get update -y

echo "==> Installing required packages: ${INSTALL_INSTALLER_DEPS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${INSTALL_INSTALLER_DEPS[@]}"

# ---------------------------------------------------------------------------
# Step 2 (optional): a modern terminal emulator (per OpenCode prerequisites).
# ---------------------------------------------------------------------------
if [[ "$SKIP_TERMINAL" != "true" ]]; then
    TERMINAL_PKGS=(kitty)
    echo "==> Installing optional modern terminal emulator: ${TERMINAL_PKGS[*]}"
    echo "    (Skip with --skip-terminal. gnome-terminal also works.)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        "${TERMINAL_PKGS[@]}"
fi

# ---------------------------------------------------------------------------
# Step 3: download the official installer and the release binary as the real
# user. GitHub release downloads occasionally reset mid-transfer, so curl is
# given its own retry settings; this is far more reliable than re-running the
# official installer, whose internal download has no retry logic.
# ---------------------------------------------------------------------------
INSTALLER_TMP="${TMPDIR:-/tmp}/opencode-install-pid$$"
mkdir -p "$INSTALLER_TMP"
chown "$REAL_USER":"$REAL_USER" "$INSTALLER_TMP"

fetch() {
    local url="$1"
    local dest="$2"
    MAX_CURL_ATTEMPTS=${MAX_CURL_ATTEMPTS:-8}
    for attempt in $(seq 1 "$MAX_CURL_ATTEMPTS"); do
        echo "    Fetching $dest (attempt $attempt/$MAX_CURL_ATTEMPTS)..."
        if curl -fSL --retry 3 --retry-delay 2 --retry-all-errors \
              -o "$dest" "$url" 2>"$INSTALLER_TMP/curl.err"; then
            echo "    Fetched $dest ($(wc -c < "$dest") bytes)."
            return 0
        fi
        sleep 3
    done
    echo "Error: failed to download $url after $MAX_CURL_ATTEMPTS attempts" >&2
    tail -3 "$INSTALLER_TMP/curl.err" >&2 2>/dev/null || true
    return 1
}

# Match the release asset name the official installer expects.
ARCH="$(uname -m)"
if [[ "$ARCH" == "aarch64" ]]; then ARCH="arm64"; fi
if [[ "$ARCH" == "x86_64" ]]; then ARCH="x64"; fi
COMBO="linux-${ARCH}"

IS_MUSL=false
if [ -f /etc/alpine-release ]; then
    IS_MUSL=true
elif command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    IS_MUSL=true
fi

if [[ "$ARCH" == "x64" ]] \
    && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
    COMBO="${COMBO}-baseline"
fi
if [[ "$IS_MUSL" == "true" ]]; then
    COMBO="${COMBO}-musl"
fi
if [[ "$COMBO" != "linux-x64" && "$COMBO" != "linux-x64-baseline"
    && "$COMBO" != "linux-x64-musl" && "$COMBO" != "linux-x64-baseline-musl"
    && "$COMBO" != "linux-arm64" && "$COMBO" != "linux-arm64-musl" ]]; then
    echo "Error: unsupported architecture: $COMBO" >&2
    exit 1
fi

DOWNLOAD_URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode-${COMBO}.tar.gz"
if [[ -n "$VERSION" ]]; then
    DOWNLOAD_URL="https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-${COMBO}.tar.gz"
fi

echo "==> Downloading opencode ($COMBO) as $REAL_USER..."
sudo -H -u "$REAL_USER" -- bash -c "
    INSTALLER_TMP='$INSTALLER_TMP'
    COMBO='$COMBO'
    DOWNLOAD_URL='$DOWNLOAD_URL'
    $(declare -f fetch)
    mkdir -p \"\$INSTALLER_TMP\"
    fetch 'https://opencode.ai/install'        \"\$INSTALLER_TMP/install.sh\" || exit 1
    fetch \"\$DOWNLOAD_URL\"                    \"\$INSTALLER_TMP/opencode-\$COMBO.tar.gz\" || exit 1
    tar -xzf \"\$INSTALLER_TMP/opencode-\$COMBO.tar.gz\" -C \"\$INSTALLER_TMP\"
    chmod 755 \"\$INSTALLER_TMP/opencode\"
"

# ---------------------------------------------------------------------------
# Step 4: run the official OpenCode installer with the local binary.
# The installer handles the $PATH setup in your shell rc file, so it must run
# as the real user (it writes to $HOME), not as root.
# ---------------------------------------------------------------------------
OC_ARGS=(--binary "$INSTALLER_TMP/opencode")
if [[ "$NO_MODIFY_PATH" == "true" ]]; then
    OC_ARGS+=(--no-modify-path)
fi

echo "==> Running the official OpenCode installer (as $REAL_USER)..."
sudo -H -u "$REAL_USER" -- bash "$INSTALLER_TMP/install.sh" "${OC_ARGS[@]}"

rm -rf "$INSTALLER_TMP"

# ---------------------------------------------------------------------------
# Step 5: verify the installation.
# ---------------------------------------------------------------------------
INSTALLED_BIN="${REAL_HOME}/.opencode/bin/opencode"
if [[ -x "$INSTALLED_BIN" ]]; then
    echo "==> OpenCode installed successfully:"
    sudo -H -u "$REAL_USER" -- "$INSTALLED_BIN" --version
else
    echo "Error: opencode binary not found at $INSTALLED_BIN" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 5: post-install hints.
# ---------------------------------------------------------------------------
cat <<EOF

OpenCode is ready. Next steps:

  1. Open a new terminal (so PATH picks up ~/.opencode/bin), or run:
        source ~/.bashrc

  2. To use your own model/API key:
        opencode auth login

  3. Start it in a project directory:
        cd your-project && opencode

  For more details: https://opencode.ai/docs
EOF