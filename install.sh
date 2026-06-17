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

# Forge CLI pinned versions. Bump in lockstep with hashd release cuts.
GH_VERSION="2.93.0"
GLAB_VERSION="1.101.0"
BKT_VERSION="0.28.1"

install_bash_completion() {
    local bashrc="${HOME}/.bashrc"
    local tmp

    mkdir -p "$(dirname "$bashrc")"
    touch "$bashrc"
    tmp="$(mktemp)"

    # Strip any legacy hashd/wf completion lines. Use grep, not awk: minimal
    # distro/container images ship coreutils (grep) but not always gawk. grep -v
    # exits 1 when every line is filtered out (e.g. an all-completions bashrc),
    # which is not an error here, so guard with `|| true`.
    grep -vE \
        -e '^[[:space:]]*# hashd/wf shell completions[[:space:]]*$' \
        -e '^[[:space:]]*# hashd/wf completions \(managed by .* drop after v1\.0 once everyone has migrated\)[[:space:]]*$' \
        -e '^[[:space:]]*source[[:space:]]+["]?[^"]*wf-completion\.bash["]?[[:space:]]*$' \
        -e '^[[:space:]]*\[\[[^]]*wf-completion\.bash[^]]*\]\][[:space:]]*&&[[:space:]]*source[[:space:]]+["]?[^"]*wf-completion\.bash["]?[[:space:]]*$' \
        -e '^[[:space:]]*source[[:space:]]+<\(wf completion bash\)[[:space:]]*$' \
        "$bashrc" > "$tmp" || true
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

extract_semver() {
    sed -nE 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -1
}

sha256_file() {
    local path="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "$path" | cut -d' ' -f1
        return 0
    fi
    if command -v shasum &>/dev/null; then
        shasum -a 256 "$path" | cut -d' ' -f1
        return 0
    fi
    echo "ERROR: sha256sum or shasum is required to verify downloaded forge CLI archives."
    exit 1
}

forge_binary_version() {
    local binary="$1"
    "$binary" --version 2>/dev/null | extract_semver || true
}

forge_asset_name() {
    local name="$1"
    local version="$2"
    local os="$3"
    local machine="$4"
    local arch

    case "$name" in
        gh)
            case "$machine" in
                x86_64) arch="amd64" ;;
                aarch64) arch="arm64" ;;
                *) return 1 ;;
            esac
            if [ "$os" = "macosx" ]; then
                echo "gh_${version}_macOS_${arch}.zip"
            else
                echo "gh_${version}_linux_${arch}.tar.gz"
            fi
            ;;
        glab)
            case "$machine" in
                x86_64) arch="amd64" ;;
                aarch64) arch="arm64" ;;
                *) return 1 ;;
            esac
            if [ "$os" = "macosx" ]; then
                echo "glab_${version}_darwin_${arch}.tar.gz"
            else
                echo "glab_${version}_linux_${arch}.tar.gz"
            fi
            ;;
        bkt)
            case "$machine" in
                x86_64) arch="x86_64" ;;
                aarch64) arch="arm64" ;;
                *) return 1 ;;
            esac
            if [ "$os" = "macosx" ]; then
                echo "bkt_${version}_darwin_${arch}.tar.gz"
            else
                echo "bkt_${version}_linux_${arch}.tar.gz"
            fi
            ;;
        *) return 1 ;;
    esac
}

forge_download_base_url() {
    local name="$1"
    local version="$2"
    case "$name" in
        gh) echo "https://github.com/cli/cli/releases/download/v${version}" ;;
        glab) echo "https://gitlab.com/gitlab-org/cli/-/releases/v${version}/downloads" ;;
        bkt) echo "https://github.com/avivsinai/bitbucket-cli/releases/download/v${version}" ;;
        *) return 1 ;;
    esac
}

forge_checksums_name() {
    local name="$1"
    local version="$2"
    case "$name" in
        gh) echo "gh_${version}_checksums.txt" ;;
        glab|bkt) echo "checksums.txt" ;;
        *) return 1 ;;
    esac
}

verify_forge_checksum() {
    local asset="$1"
    local checksums="$2"
    local asset_name
    local expected
    local actual
    local line_sum line_file

    asset_name="$(basename "$asset")"
    # Look up the expected hash without awk (minimal images may lack gawk). The
    # checksums file is `<sha>  <filename>` per line; match the filename exactly.
    expected=""
    while read -r line_sum line_file; do
        if [ "$line_file" = "$asset_name" ]; then
            expected="$line_sum"
            break
        fi
    done < "$checksums"
    if [ -z "$expected" ]; then
        echo "ERROR: No checksum entry found for $asset_name"
        exit 1
    fi

    actual="$(sha256_file "$asset")"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: SHA256 mismatch for $asset_name"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        exit 1
    fi
}

install_forge_cli() {
    local name="$1"
    local display="$2"
    local version="$3"
    local bin_dir="${PIPX_BIN_DIR:-$HOME/.local/bin}"
    local existing_path
    local existing_version
    local asset_name
    local base_url
    local checksums_name
    local forge_dir
    local asset_path
    local checksums_path
    local extract_dir
    local found_binary
    local installed_version

    existing_path="$(command -v "$name" 2>/dev/null || true)"
    if [ -n "$existing_path" ]; then
        existing_version="$(forge_binary_version "$existing_path")"
        if [ "$existing_version" = "$version" ]; then
            echo "  $name $version already installed"
            return 0
        fi
        if [ -n "$existing_version" ]; then
            echo "  $name present at $existing_version, replacing with $version"
        else
            echo "  $name present at $existing_path, replacing with $version"
        fi
    else
        echo "  Installing $display CLI ($name) $version..."
    fi

    asset_name="$(forge_asset_name "$name" "$version" "$PLATFORM" "$MACHINE")"
    base_url="$(forge_download_base_url "$name" "$version")"
    checksums_name="$(forge_checksums_name "$name" "$version")"
    forge_dir="$WORK_DIR/forge-$name"
    asset_path="$forge_dir/$asset_name"
    checksums_path="$forge_dir/$checksums_name"
    extract_dir="$forge_dir/extract"

    mkdir -p "$extract_dir"
    curl -fsSL -o "$asset_path" "$base_url/$asset_name"
    curl -fsSL -o "$checksums_path" "$base_url/$checksums_name"
    verify_forge_checksum "$asset_path" "$checksums_path"

    case "$asset_name" in
        *.tar.gz)
            tar -xzf "$asset_path" -C "$extract_dir"
            ;;
        *.zip)
            if ! command -v unzip &>/dev/null; then
                echo "ERROR: unzip is required to extract $asset_name"
                exit 1
            fi
            unzip -q "$asset_path" -d "$extract_dir"
            ;;
        *)
            echo "ERROR: Unsupported forge CLI archive: $asset_name"
            exit 1
            ;;
    esac

    found_binary="$(find "$extract_dir" -name "$name" -type f -perm -u+x | head -1)"
    if [ -z "$found_binary" ]; then
        found_binary="$(find "$extract_dir" -name "$name" -type f | head -1)"
    fi
    if [ -z "$found_binary" ]; then
        echo "ERROR: Could not find $name inside $asset_name"
        exit 1
    fi

    mkdir -p "$bin_dir"
    install -m 755 "$found_binary" "$bin_dir/$name"
    installed_version="$("$bin_dir/$name" --version 2>/dev/null | extract_semver || true)"
    if [ "$installed_version" != "$version" ]; then
        echo "ERROR: Installed $name but version check returned '${installed_version:-unknown}', expected $version"
        exit 1
    fi
    echo "  Installed $name $version at $bin_dir/$name"
}

warn_external_tools() {
    echo "WARN: external tool install skipped ($1)."
    echo "      gitleaks can be installed manually from https://github.com/gitleaks/gitleaks/releases if needed."
    echo "      git-delta can be installed manually from https://github.com/dandavison/delta/releases if needed."
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
echo ""
echo "This installer will install:"
echo "  - pipx (if missing)"
echo "  - hashd Python wheels (CLI + server + bot/figma/jira/github connectors + TUI)"
echo "  - Forge CLIs: gh (GitHub), glab (GitLab), bkt (Bitbucket) -- pinned versions, prebuilt binaries"
echo "  - External runtime tools: gitleaks, git-delta -- pinned versions, prebuilt binaries"
echo "You still need (not installed automatically):"
echo "  - At least one AI agent CLI (claude / codex / cursor-agent)"
echo "After install, run \`wf doctor\` to verify everything is wired up."

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

# --- Install forge CLIs ---
echo ""
echo "Installing forge CLIs..."
install_forge_cli gh "GitHub" "$GH_VERSION"
install_forge_cli glab "GitLab" "$GLAB_VERSION"
install_forge_cli bkt "Bitbucket" "$BKT_VERSION"

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

# --- Install external tools (gitleaks, git-delta, ...) ---
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
#    install-tools.sh pins the tool versions itself, so a wheel
#    user today always gets the script's current pins regardless of
#    when they install.
#    The latent risk: if we ever ship wf code that depends on a
#    specific tool version's output shape (say, gitleaks 9.x
#    reshuffles the JSON fields wf parses) and later bump the
#    script's pin, old wheels in the wild start getting the new
#    tool. Revisit this pin at that point: either switch to
#    $RELEASE_TAG, or freeze per-tool versions per wheel release.
TOOLS_SCRIPT_URL="https://raw.githubusercontent.com/$REPO/main/scripts/install-tools.sh"
TOOLS_OS="$PLATFORM"
if [ "$TOOLS_OS" = "macosx" ]; then
    TOOLS_OS="darwin"
fi
TOOLS_ARCH="$MACHINE"
case "$TOOLS_ARCH" in
    x86_64) TOOLS_ARCH="amd64" ;;
    aarch64) TOOLS_ARCH="arm64" ;;
esac
echo ""
echo "Installing external tools..."
if curl --fail --silent --location \
    --retry 3 --retry-delay 2 \
    --connect-timeout 10 --max-time 60 \
    "$TOOLS_SCRIPT_URL" -o "$WORK_DIR/install-tools.sh" 2>/dev/null; then
    if ! HASHD_TOOLS_OS="$TOOLS_OS" HASHD_TOOLS_ARCH="$TOOLS_ARCH" bash "$WORK_DIR/install-tools.sh"; then
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
echo "Forge auth not yet configured. Authenticate for the forge(s) you use:"
echo "  gh:   gh auth login"
echo "  glab: glab auth login"
echo "  bkt:  bkt auth login --kind cloud --web"
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
