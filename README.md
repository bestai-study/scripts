# bestai-study / scripts

Tested shell scripts for installing terminal AI coding agents on Ubuntu 24.04 LTS (Noble). Each script uses the vendor's official installer or repository, takes care of the apt dependencies around it, and runs the application part as your normal user.

Every script passed `bash -n` and was tested end to end in a clean `ubuntu:24.04` Docker container before publishing. The test matrix for each is documented in the matching article on [bestai.study](https://bestai.study).

All scripts are run as your normal user; they elevate with `sudo` only where apt needs it.

## install-opencode-ubuntu24.sh

Installs [OpenCode](https://opencode.ai), an open-source AI coding agent for the terminal, from the official OpenCode installer in `--binary` mode. The binary lands in `~/.opencode/bin` and your shell PATH is updated in `~/.bashrc`.

```bash
curl -fsSL https://bestai.study/downloads/install-opencode-ubuntu24.sh -o install-opencode-ubuntu24.sh
chmod +x install-opencode-ubuntu24.sh
./install-opencode-ubuntu24.sh
```

| Option | What it does |
|---|---|
| `-v, --version <ver>` | Install a specific release, e.g. `--version 1.0.180`. Defaults to latest. |
| `-s, --skip-terminal` | Skip the optional kitty terminal emulator (requires sudo apt access). |
| `--no-modify-path` | Do not touch `~/.bashrc` (or other shell rc files) for the PATH entry. |
| `-h, --help` | Print usage and exit. |

Example on a headless box, pinned version, no rc edits:

```bash
./install-opencode-ubuntu24.sh --version 1.0.180 --skip-terminal --no-modify-path
```

Guide: https://bestai.study/posts/install-opencode-ubuntu-24/

## install-codex-ubuntu24.sh

Installs the [Codex CLI](https://developers.openai.com/codex), OpenAI's coding agent for the terminal, from the official standalone installer (`curl -fsSL https://chatgpt.com/codex/install.sh`). The native binary lands in `~/.local/bin/codex` and your shell PATH is updated.

```bash
curl -fsSL https://bestai.study/downloads/install-codex-ubuntu24.sh -o install-codex-ubuntu24.sh
chmod +x install-codex-ubuntu24.sh
./install-codex-ubuntu24.sh
```

| Option | What it does |
|---|---|
| `-v, --version <ver>` | Install a specific release, e.g. `--version 0.154.0`. Defaults to latest. |
| `-h, --help` | Print usage and exit. |

On networks where `chatgpt.com` is unreachable (e.g. mainland China), route the download through a proxy first:

```bash
HTTPS_PROXY=http://127.0.0.1:7890 ./install-codex-ubuntu24.sh
```

As a last resort, point the script at a reachable mirror of the official installer:

```bash
CODEX_INSTALLER_URL=https://example.com/codex-install.sh ./install-codex-ubuntu24.sh
```

Guide: https://bestai.study/posts/install-codex-ubuntu-24/

## install-claude-code-ubuntu24.sh

Installs [Claude Code](https://code.claude.com), Anthropic's coding agent for the terminal, from Anthropic's official signed apt repository. The script downloads the signing key, verifies its fingerprint against the published value, registers the repository, then installs `claude-code` with apt.

```bash
curl -fsSL https://bestai.study/downloads/install-claude-code-ubuntu24.sh -o install-claude-code-ubuntu24.sh
chmod +x install-claude-code-ubuntu24.sh
./install-claude-code-ubuntu24.sh
```

| Option | What it does |
|---|---|
| `-c, --channel <name>` | apt channel: `stable` (default) or `latest`. |
| `-h, --help` | Print usage and exit. |

On networks where `downloads.claude.ai` is unreachable (e.g. mainland China), route the download through a proxy first:

```bash
HTTPS_PROXY=http://127.0.0.1:7890 ./install-claude-code-ubuntu24.sh
```

Guide: https://bestai.study/posts/install-claude-code-ubuntu-24/

## This repository

This repository is a published mirror of the scripts also served for download from the site (https://bestai.study/downloads/). The versioned copy lives in the bestai.study site repository; this mirror should be kept byte-identical.