#!/bin/bash
# hashd installer
# Usage: curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
# Intended for packaged wheel installs/upgrades.
# This script should be safe to re-run; install, migration, and restart work
# are expected to be idempotent.
set -e

REPO="codr1/hashd-code"
COMPLETION_MARKER="# hashd/wf completions (managed by hashd install scripts -- drop after v1.0 once everyone has migrated)"
COMPLETION_LINE='source <(wf completion bash)'

install_bash_completion() {
    local bashrc="${HOME}/.bashrc"
    local tmp

    mkdir -p "$(dirname "$bashrc")"
    touch "$bashrc"
    tmp="$(mktemp)"

    awk '
        /^[[:space:]]*# hashd\/wf shell completions[[:space:]]*$/ { next }
        /^[[:space:]]*# hashd\/wf completions \(managed by .* drop after v1\.0 once everyone has migrated\)[[:space:]]*$/ { next }
        /^[[:space:]]*source[[:space:]]+["]?[^"]*wf-completion\.bash["]?[[:space:]]*$/ { next }
        /^[[:space:]]*\[\[[^]]*wf-completion\.bash[^]]*\]\][[:space:]]*&&[[:space:]]*source[[:space:]]+["]?[^"]*wf-completion\.bash["]?[[:space:]]*$/ { next }
        /^[[:space:]]*source[[:space:]]+<\(wf completion bash\)[[:space:]]*$/ { next }
        { print }
    ' "$bashrc" > "$tmp"
    mv "$tmp" "$bashrc"

    if [[ -s "$bashrc" ]]; then
        printf '\n' >> "$bashrc"
    fi
    printf '%s\n%s\n' "$COMPLETION_MARKER" "$COMPLETION_LINE" >> "$bashrc"
}

promote_pipx_binary() {
    local name="$1"
    local bin_dir="${PIPX_BIN_DIR:-$HOME/.local/bin}"
    local pipx_home="${PIPX_HOME:-$HOME/.local/pipx}"
    local target="${bin_dir}/${name}"
    local source="${pipx_home}/venvs/hashd/bin/${name}"

    if [ -x "$target" ]; then
        return 0
    fi
    if [ ! -x "$source" ]; then
        return 1
    fi

    mkdir -p "$bin_dir"
    ln -sf "$source" "$target"
}

extract_first_major_minor() {
    sed -nE 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/p' | head -1
}

extract_json_string_field() {
    local field="$1"
    sed -nE "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\\1/p" | head -1
}

warn_external_tools() {
    echo "WARN: external tool install skipped ($1)."
    echo "      gitleaks can be installed manually from https://github.com/gitleaks/gitleaks/releases if needed."
}

# --- Detect platform ---
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)  PLATFORM="linux" ;;
    Darwin) PLATFORM="macosx" ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64)  MACHINE="x86_64" ;;
    aarch64|arm64) MACHINE="aarch64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "hashd installer"
echo ""
echo "  Platform: $PLATFORM ($MACHINE)"

# --- Check Python ---
PYTHON=""
PYTHON_VERSION=""
for cmd in python3.14 python3.13 python3.12 python3.11 python3; do
    if command -v "$cmd" &>/dev/null; then
        version=$("$cmd" --version 2>&1 | extract_first_major_minor)
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)
        if [ -n "$major" ] && [ -n "$minor" ] && { [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 11 ]; }; }; then
            PYTHON="$cmd"
            PYTHON_VERSION="$version"
            echo "  Python:   $version ($cmd)"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo ""
    echo "ERROR: Python 3.11+ is required."
    echo ""
    echo "  Install Python:"
    echo "    Arch:          sudo pacman -S python"
    echo "    Debian/Ubuntu: sudo apt install python3"
    echo "    macOS:         brew install python@3.14"
    echo "    Or:            https://www.python.org/downloads/"
    exit 1
fi

# --- Check/install pipx ---
if ! command -v pipx &>/dev/null; then
    echo ""
    echo "Installing pipx..."
    # Try ensurepip first (bootstraps pip on systems that ship without it)
    if ! "$PYTHON" -m pip --version &>/dev/null; then
        "$PYTHON" -m ensurepip --user 2>/dev/null || true
    fi
    if ! "$PYTHON" -m pip install --user pipx 2>/dev/null; then
        if command -v uv &>/dev/null && uv tool install pipx >/dev/null 2>&1; then
            export PATH="$HOME/.local/bin:$PATH"
        else
            echo ""
            echo "ERROR: Could not install pipx (pip is not available)."
            echo ""
            echo "  Install pipx for your platform, then re-run this script:"
            echo "    Debian/Ubuntu: sudo apt update && sudo apt install pipx"
            echo "    Arch:          sudo pacman -S python-pipx"
            echo "    macOS:         brew install pipx"
            exit 1
        fi
    fi
    export PATH="$HOME/.local/bin:$PATH"
    pipx ensurepath 2>/dev/null || "$PYTHON" -m pipx ensurepath 2>/dev/null || true
fi

echo "  pipx:     $(pipx --version 2>/dev/null || echo 'installed')"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Find latest release ---
echo ""
echo "Finding latest release..."

# Try gh CLI first, fall back to curl. A local gh install is not enough:
# fresh machines often have gh on PATH before `gh auth login` has run.
USE_GH_RELEASE_DOWNLOAD=0
if command -v gh &>/dev/null; then
    GH_RELEASE_ERR="$WORK_DIR/gh-release-view.err"
    if RELEASE_TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName 2>"$GH_RELEASE_ERR") && [ -n "$RELEASE_TAG" ]; then
        USE_GH_RELEASE_DOWNLOAD=1
    else
        if [ -s "$GH_RELEASE_ERR" ]; then
            echo "  gh CLI is unauthenticated or cannot read releases; falling back to curl."
        fi
        RELEASE_TAG=""
    fi
fi
if [ -z "$RELEASE_TAG" ]; then
    RELEASE_TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | extract_json_string_field "tag_name" || echo "")
fi

if [ -z "$RELEASE_TAG" ]; then
    echo "ERROR: No releases found at github.com/$REPO"
    echo "  Check https://github.com/$REPO/releases"
    exit 1
fi

echo "  Latest:   $RELEASE_TAG"

# --- Find matching wheel ---
# Wheels use abi3 stable ABI (cp311-abi3): works with any Python 3.11+.
# If minimum Python changes, update this tag AND pyproject.toml requires-python.
ABI_TAG="cp311-abi3"

# macOS wheels use "universal2" instead of arch-specific names
if [ "$PLATFORM" = "macosx" ]; then
    WHEEL_MACHINE="universal2"
else
    WHEEL_MACHINE="$MACHINE"
fi

WHEEL_PATTERN="hashd-*-${ABI_TAG}-*${WHEEL_MACHINE}*.whl"
BOT_WHEEL_PATTERN="hashd_bot_telegram-*.whl"
FIGMA_WHEEL_PATTERN="hashd_connector_figma-*.whl"
GITHUB_CONNECTOR_WHEEL_PATTERN="hashd_connector_github-*.whl"
JIRA_WHEEL_PATTERN="hashd_connector_jira-*.whl"
TUI_WHEEL_PATTERN="hashd_tui-*.whl"

echo "  Looking for: $WHEEL_PATTERN"

# Download matching wheel
if [ "$USE_GH_RELEASE_DOWNLOAD" -eq 1 ]; then
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$BOT_WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$FIGMA_WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$GITHUB_CONNECTOR_WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$JIRA_WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$TUI_WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
else
    # Fall back to curl from release assets
    ASSETS_URL="https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG"
    WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
        | grep '"browser_download_url"' \
        | grep "$WHEEL_MACHINE" \
        | grep "$ABI_TAG" \
        | head -1 \
        | extract_json_string_field "browser_download_url")

    if [ -z "$WHEEL_URL" ]; then
        echo ""
        echo "ERROR: No wheel found for Python $PYTHON_VERSION on $PLATFORM/$MACHINE"
        echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
        exit 1
    fi

    curl -fsSL -o "$WORK_DIR/$(basename "$WHEEL_URL")" "$WHEEL_URL"

    BOT_WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
        | grep '"browser_download_url"' \
        | grep 'hashd_bot_telegram-' \
        | head -1 \
        | extract_json_string_field "browser_download_url")

    if [ -z "$BOT_WHEEL_URL" ]; then
        echo ""
        echo "ERROR: No Telegram bot wheel found"
        echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
        exit 1
    fi

    curl -fsSL -o "$WORK_DIR/$(basename "$BOT_WHEEL_URL")" "$BOT_WHEEL_URL"

    FIGMA_WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
        | grep '"browser_download_url"' \
        | grep 'hashd_connector_figma-' \
        | head -1 \
        | extract_json_string_field "browser_download_url")

    if [ -z "$FIGMA_WHEEL_URL" ]; then
        echo ""
        echo "ERROR: No Figma connector wheel found"
        echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
        exit 1
    fi

    curl -fsSL -o "$WORK_DIR/$(basename "$FIGMA_WHEEL_URL")" "$FIGMA_WHEEL_URL"

    GITHUB_CONNECTOR_WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
        | grep '"browser_download_url"' \
        | grep 'hashd_connector_github-' \
        | head -1 \
        | extract_json_string_field "browser_download_url")

    if [ -z "$GITHUB_CONNECTOR_WHEEL_URL" ]; then
        echo ""
        echo "ERROR: No GitHub connector wheel found"
        echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
        exit 1
    fi

    curl -fsSL -o "$WORK_DIR/$(basename "$GITHUB_CONNECTOR_WHEEL_URL")" "$GITHUB_CONNECTOR_WHEEL_URL"

    JIRA_WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
        | grep '"browser_download_url"' \
        | grep 'hashd_connector_jira-' \
        | head -1 \
        | extract_json_string_field "browser_download_url")

    if [ -z "$JIRA_WHEEL_URL" ]; then
        echo ""
        echo "ERROR: No Jira connector wheel found"
        echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
        exit 1
    fi

    curl -fsSL -o "$WORK_DIR/$(basename "$JIRA_WHEEL_URL")" "$JIRA_WHEEL_URL"

    TUI_WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
        | grep '"browser_download_url"' \
        | grep 'hashd_tui-' \
        | head -1 \
        | extract_json_string_field "browser_download_url")

    if [ -z "$TUI_WHEEL_URL" ]; then
        echo ""
        echo "ERROR: No TUI wheel found"
        echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
        exit 1
    fi

    curl -fsSL -o "$WORK_DIR/$(basename "$TUI_WHEEL_URL")" "$TUI_WHEEL_URL"
fi

WHEEL=$(find "$WORK_DIR" -name "$WHEEL_PATTERN" | head -1)
if [ -z "$WHEEL" ]; then
    echo ""
    echo "ERROR: No wheel found for $PLATFORM/$MACHINE"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi
BOT_WHEEL=$(find "$WORK_DIR" -name "$BOT_WHEEL_PATTERN" | head -1)
if [ -z "$BOT_WHEEL" ]; then
    echo ""
    echo "ERROR: Telegram bot wheel not found"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi
FIGMA_WHEEL=$(find "$WORK_DIR" -name "$FIGMA_WHEEL_PATTERN" | head -1)
if [ -z "$FIGMA_WHEEL" ]; then
    echo ""
    echo "ERROR: Figma connector wheel not found"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi
GITHUB_CONNECTOR_WHEEL=$(find "$WORK_DIR" -name "$GITHUB_CONNECTOR_WHEEL_PATTERN" | head -1)
if [ -z "$GITHUB_CONNECTOR_WHEEL" ]; then
    echo ""
    echo "ERROR: GitHub connector wheel not found"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi
JIRA_WHEEL=$(find "$WORK_DIR" -name "$JIRA_WHEEL_PATTERN" | head -1)
if [ -z "$JIRA_WHEEL" ]; then
    echo ""
    echo "ERROR: Jira connector wheel not found"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi
TUI_WHEEL=$(find "$WORK_DIR" -name "$TUI_WHEEL_PATTERN" | head -1)
if [ -z "$TUI_WHEEL" ]; then
    echo ""
    echo "ERROR: TUI wheel not found"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi

echo "  Downloaded: $(basename "$WHEEL")"
echo "  Downloaded: $(basename "$BOT_WHEEL")"
echo "  Downloaded: $(basename "$FIGMA_WHEEL")"
echo "  Downloaded: $(basename "$GITHUB_CONNECTOR_WHEEL")"
echo "  Downloaded: $(basename "$JIRA_WHEEL")"
echo "  Downloaded: $(basename "$TUI_WHEEL")"

# --- Install ---
echo ""
echo "Installing hashd..."
pipx install --force "$WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
pipx runpip hashd install --upgrade "$BOT_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
pipx runpip hashd install --upgrade "$FIGMA_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
pipx runpip hashd install --upgrade "$GITHUB_CONNECTOR_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
pipx runpip hashd install --upgrade "$JIRA_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
pipx runpip hashd install --upgrade "$TUI_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'

# Ensure ~/.local/bin is on PATH
pipx ensurepath 2>/dev/null || true

OPS_ROOT="${HASHD_OPS_ROOT:-$HOME/.hashd}"
mkdir -p "$OPS_ROOT"/{projects,workstreams,worktrees,runs,locks,cache,secrets,config}
WF_BIN="${PIPX_BIN_DIR:-$HOME/.local/bin}/wf"
promote_pipx_binary wf || true
promote_pipx_binary hashd-server || true
if [ ! -x "$WF_BIN" ]; then
    echo ""
    echo "ERROR: Installed wf not found at $WF_BIN"
    echo "  Expected bundled binary at: ${PIPX_HOME:-$HOME/.local/pipx}/venvs/hashd/bin/wf"
    exit 1
fi

install_bash_completion

# --- Install external tools (gitleaks, ...) ---
# Delegates to scripts/install-tools.sh from main -- the same script
# `wf` auto-invokes on source checkouts when a tool is missing. One
# script, two entry points, no drift.
#
# Why main, not $RELEASE_TAG:
#
# 1. Backward-compat: pinning to $RELEASE_TAG 404s on any tag
#    predating this script's introduction. install.sh itself is
#    always fetched from main, so there's no "old installer on
#    disk" to stay compatible with -- but fetching the tools script
#    from an arbitrary old tag would break.
#
# 2. Forward-drift tradeoff (acknowledged, not yet a problem):
#    install-tools.sh pins the gitleaks version itself, so a wheel
#    user today always gets 8.30.1 regardless of when they install.
#    The latent risk: if we ever ship wf code that depends on a
#    specific tool version's output shape (say, gitleaks 9.x
#    reshuffles the JSON fields wf parses) and later bump the
#    script's pin, old wheels in the wild start getting the new
#    tool. Revisit this pin at that point: either switch to
#    $RELEASE_TAG, or freeze per-tool versions per wheel release.
TOOLS_SCRIPT_URL="https://raw.githubusercontent.com/$REPO/main/scripts/install-tools.sh"
echo ""
echo "Installing external tools..."
if curl --fail --silent --location \
    --retry 3 --retry-delay 2 \
    --connect-timeout 10 --max-time 60 \
    "$TOOLS_SCRIPT_URL" -o "$WORK_DIR/install-tools.sh" 2>/dev/null; then
    if ! bash "$WORK_DIR/install-tools.sh"; then
        warn_external_tools "installer script failed"
    fi
else
    warn_external_tools "could not download installer script"
fi

echo ""
echo "Refreshing services and project databases..."
"$WF_BIN" restart --yes

echo ""
echo "Done! Installed hashd $RELEASE_TAG."
echo ""
if ! command -v wf &>/dev/null; then
    echo "NOTE: wf is not yet on your PATH. Run:"
    echo ""
    echo "  source ~/.bashrc"
    echo ""
    echo "Or open a new terminal."
    echo ""
fi
echo "Next steps:"
echo ""
echo "  wf --help"
echo "  wf project add /path/to/your/repo"
echo ""
