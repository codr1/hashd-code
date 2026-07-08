#!/bin/bash
# hashd installer
# Usage: curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
# Intended for packaged wheel installs/upgrades.
# This script should be safe to re-run; install, migration, and restart work
# are expected to be idempotent.
set -e

REPO="codr1/hashd-code"
COMPLETION_MARKER="# hashd/wf completions (managed by hashd install scripts -- drop after v1.0 once everyone has migrated)"

# Forge CLI pinned versions. Bump in lockstep with hashd release cuts.
GH_VERSION="2.93.0"
GLAB_VERSION="1.101.0"
BKT_VERSION="0.28.1"
TEA_VERSION="0.14.1"

# --- Output: restrained color + step markers ---
#
# Quiet by default: one line per real step. Color is used sparingly and only
# when stdout is a TTY and NO_COLOR is unset (https://no-color.org). Errors
# render in the same error:/-->/Suggestions: shape as server/internal/diagnostic
# so the installer and `hashd doctor` speak with one voice.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_GREEN=$'\033[32m'
    C_BLUE=$'\033[34m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""
    C_BLUE=""
    C_DIM=""
    C_BOLD=""
    C_RED=""
    C_RESET=""
fi

# step: announce the start of a real step ("-> doing the thing").
step() {
    printf '%s->%s %s\n' "$C_BLUE" "$C_RESET" "$1"
}

# ok: confirm a step finished ("  + result"), optionally with dim detail.
ok() {
    if [ -n "${2:-}" ]; then
        printf '  %s+%s %s %s%s%s\n' "$C_GREEN" "$C_RESET" "$1" "$C_DIM" "$2" "$C_RESET"
    else
        printf '  %s+%s %s\n' "$C_GREEN" "$C_RESET" "$1"
    fi
}

# verified: surface the SHA-256 check the installer already performs.
verified() {
    printf '  %s+%s %s %sverified%s\n' "$C_GREEN" "$C_RESET" "$1" "$C_DIM" "$C_RESET"
}

# note: dim, secondary information.
note() {
    printf '  %s%s%s\n' "$C_DIM" "$1" "$C_RESET"
}

# die: render a structured diagnostic and exit non-zero.
#
# Usage: die "<title>" "<source>" "<explanation>" "<help line>" ["<help line>" ...]
# The explanation may contain literal "\n" for multi-line context. Help lines
# render as a "Suggestions:" bullet list -- give the ONE OS-correct fix command,
# not a multi-platform menu.
die() {
    local title="$1" source="$2" explanation="$3"
    shift 3
    printf '%serror:%s %s\n' "${C_RED}${C_BOLD}" "$C_RESET" "$title" >&2
    if [ -n "$source" ]; then
        printf '  --> %s\n' "$source" >&2
    fi
    if [ -n "$explanation" ]; then
        printf '\n' >&2
        printf '%b\n' "$explanation" | while IFS= read -r line; do
            printf '  %s\n' "$line" >&2
        done
    fi
    if [ "$#" -gt 0 ]; then
        printf '\nSuggestions:\n' >&2
        local hint
        for hint in "$@"; do
            printf '  - %s\n' "$hint" >&2
        done
    fi
    exit 1
}

# --- uv bootstrap ---
#
# The Python -> pip -> pipx -> PEP-668 gauntlet hard-errors on a fresh modern
# box (Arch, Homebrew Python) where the system interpreter is
# externally-managed. uv sidesteps all of it: a single curl install with zero
# prereqs that can both provide a Python 3.11+ runtime and install the wheels
# via its pipx-equivalent (`uv tool install` + `--with` injected wheels).

UV_BIN=""

# uv_path: locate uv, preferring an already-on-PATH copy, then the standard
# installer location. Echoes the resolved path; returns non-zero if absent.
uv_path() {
    if command -v uv &>/dev/null; then
        command -v uv
        return 0
    fi
    if [ -x "$HOME/.local/bin/uv" ]; then
        echo "$HOME/.local/bin/uv"
        return 0
    fi
    return 1
}

# python_pipx_healthy: true when a usable Python 3.11+ AND a working pipx are
# both present. This is the "healthy existing toolchain" fast path -- when it
# holds, we keep using pipx exactly as before and never touch uv.
python_pipx_healthy() {
    [ -n "$PYTHON" ] || return 1
    command -v pipx &>/dev/null || return 1
    return 0
}

# pip_pipx_install_blocked: probe whether `pip install --user pipx` is viable.
# Returns 0 (blocked) when pip is missing or refuses with PEP-668
# "externally-managed-environment", which is the default on modern Arch and
# Homebrew Python. Returns 1 (not blocked) when pip can install user packages.
# Does not actually install -- uses a dry-run probe so the real install path
# stays a single code path.
pip_pipx_install_blocked() {
    [ -n "$PYTHON" ] || return 0
    if ! "$PYTHON" -m pip --version &>/dev/null; then
        return 0
    fi
    local probe
    probe="$("$PYTHON" -m pip install --user --dry-run pipx 2>&1)" || {
        case "$probe" in
            *externally-managed-environment*|*externally\ managed*)
                return 0
                ;;
        esac
        # Some pip versions reject --dry-run; fall back to treating a generic
        # failure as "not blocked" so the real attempt can decide.
        case "$probe" in
            *"no such option"*|*"unrecognized arguments"*)
                return 1
                ;;
        esac
        return 0
    }
    return 1
}

# bootstrap_uv: ensure uv is installed, curl-bootstrapping it if missing.
# Sets UV_BIN to the resolved path. uv's installer needs no Python and no root.
bootstrap_uv() {
    if UV_BIN="$(uv_path)"; then
        ok "uv" "$("$UV_BIN" --version 2>/dev/null | extract_semver || echo present)"
        return 0
    fi
    step "Installing uv (provides Python 3.11+, no prerequisites)"
    if ! curl -fsSL https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; then
        die "Could not install uv" \
            "install.uv_bootstrap" \
            "uv is hashd's zero-prerequisite path to a Python 3.11+ runtime, and the curl bootstrap from https://astral.sh failed.\nThis usually means no network access or a proxy blocking astral.sh." \
            "Install uv manually: https://docs.astral.sh/uv/getting-started/installation/" \
            "Then re-run: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    if ! UV_BIN="$(uv_path)"; then
        die "uv installed but not found on PATH" \
            "install.uv_bootstrap" \
            "The uv installer ran but uv is not on PATH at \$HOME/.local/bin/uv." \
            "Open a new shell or run: export PATH=\"\$HOME/.local/bin:\$PATH\"" \
            "Then re-run: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
    fi
    ok "uv installed" "$("$UV_BIN" --version 2>/dev/null | extract_semver || echo present)"
}

# install_via_uv: install hashd + all extra wheels through uv's pipx-equivalent.
# `uv tool install` makes the primary wheel's entry points (hashd, wf, ha,
# hashd-server)
# available on PATH; `--with` injects the bot/connector/tui wheels into the same
# managed environment. uv provides a Python 3.11+ interpreter itself, so this
# works even when the host has no system Python.
install_via_uv() {
    step "Installing hashd via uv (Python 3.11+ managed by uv)"
    "$UV_BIN" tool install --force --python 3.11 \
        --with "$CLIENT_WHEEL" \
        --with "$BOT_WHEEL" \
        --with "$FIGMA_WHEEL" \
        --with "$GITHUB_CONNECTOR_WHEEL" \
        --with "$JIRA_WHEEL" \
        --with "$TUI_WHEEL" \
        "$WHEEL"
    # uv tool installs land in ~/.local/bin by default; make sure it's wired up.
    "$UV_BIN" tool update-shell >/dev/null 2>&1 || true
    export PATH="$HOME/.local/bin:$PATH"
}

# install_via_pipx: the classic healthy-toolchain path. Unchanged behavior:
# pipx owns the primary wheel, runpip injects the extras.
install_via_pipx() {
    step "Installing hashd via pipx"
    pipx install --force --pip-args "--find-links $WORK_DIR" "$WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$CLIENT_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$BOT_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$FIGMA_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$GITHUB_CONNECTOR_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$JIRA_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$TUI_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx ensurepath 2>/dev/null || true
}

# node_install_hint: the ONE OS-correct command to install a Node.js runtime,
# used in the agent on-ramp printed at finish. Agents are npm-installed, so Node
# is the agent's prerequisite -- not hashd's.
node_install_hint() {
    if [ "$PLATFORM" = "macosx" ]; then
        echo "brew install node"
    else
        echo "https://github.com/nvm-sh/nvm  then: nvm install 20"
    fi
}

# rc_targets: the shell rc files the installer manages (PATH + completions).
# Always ~/.bashrc (bash). macOS Terminal runs zsh and never sources ~/.bashrc,
# so include ~/.zshrc on macOS -- and on Linux too when the login shell is zsh.
# Without this the freshly installed hashd/wf entry points and the bundled tools
# never land on the zsh PATH, and `hashd`/`wf` read as command-not-found.
rc_targets() {
    printf '%s\n' "$HOME/.bashrc"
    case "${SHELL:-}" in
        *zsh*) printf '%s\n' "$HOME/.zshrc"; return ;;
    esac
    [ "${PLATFORM:-}" = "macosx" ] && printf '%s\n' "$HOME/.zshrc"
}

# ensure_dir_on_path: put DIR on PATH for the rest of this run and persist it
# into every rc_targets file, keyed by MARKER so re-runs don't duplicate. Used
# for the entry-points dir (~/.local/bin -- uv/pipx wire it for bash but not
# reliably for zsh) and the bundled-tools dir (~/.hashd/tools/bin).
ensure_dir_on_path() {
    local dir="$1" marker="$2" rc
    mkdir -p "$dir"

    # Make it effective for the rest of this install run too.
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) export PATH="$dir:$PATH" ;;
    esac

    while IFS= read -r rc; do
        mkdir -p "$(dirname "$rc")"
        touch "$rc"
        if grep -qF "$marker" "$rc"; then
            continue
        fi
        if [[ -s "$rc" ]]; then
            printf '\n' >> "$rc"
        fi
        printf '%s\nexport PATH="%s:$PATH"\n' "$marker" "$dir" >> "$rc"
    done < <(rc_targets)
}

# ensure_tools_dir_on_path: persist the bundled-tools dir (~/.hashd/tools/bin,
# honoring $HASHD_TOOLS_DIR) onto PATH. install-tools.sh drops gitleaks +
# git-delta there; without this they resolve for hashd's tools-dir-aware code
# but not as bare `gitleaks`/`delta` on the user's own PATH.
ensure_tools_dir_on_path() {
    ensure_dir_on_path "${HASHD_TOOLS_DIR:-$HOME/.hashd/tools/bin}" \
        "# hashd tools dir (managed by hashd install scripts)"
}

# install_completions: wire shell completions into each rc_targets file, per
# shell -- bash rc gets `completion bash`, zsh rc gets `completion zsh` (which
# cobra emits as a compdef script, so it needs compinit first). Idempotent: the
# prior managed block and any legacy hand-written wf-completion lines are
# stripped before the current block is appended, so re-runs don't stack.
install_completions() {
    local rc tmp block

    while IFS= read -r rc; do
        mkdir -p "$(dirname "$rc")"
        touch "$rc"
        tmp="$(mktemp)"

        # Strip the prior managed block + any legacy hashd/wf completion lines.
        # Use grep, not awk: minimal images ship coreutils (grep) but not always
        # gawk. grep -v exits 1 when every line is filtered out, which is not an
        # error here, so guard with `|| true`.
        grep -vE \
            -e '^[[:space:]]*# hashd/wf shell completions[[:space:]]*$' \
            -e '^[[:space:]]*# hashd/wf completions \(managed by .* drop after v1\.0 once everyone has migrated\)[[:space:]]*$' \
            -e '^[[:space:]]*source[[:space:]]+["]?[^"]*wf-completion\.bash["]?[[:space:]]*$' \
            -e '^[[:space:]]*\[\[[^]]*wf-completion\.bash[^]]*\]\][[:space:]]*&&[[:space:]]*source[[:space:]]+["]?[^"]*wf-completion\.bash["]?[[:space:]]*$' \
            -e '^[[:space:]]*autoload -Uz compinit && compinit -u[[:space:]]*$' \
            -e '^[[:space:]]*source[[:space:]]+<\((hashd|wf|ha) completion (bash|zsh)\)[[:space:]]*$' \
            "$rc" > "$tmp" || true
        mv "$tmp" "$rc"

        if [[ -s "$rc" ]]; then
            printf '\n' >> "$rc"
        fi
        case "$rc" in
            *.zshrc)
                # cobra's zsh completion is a compdef script; compinit must have
                # run for it to register. compinit is safe to re-run (-u skips
                # the insecure-directory prompt in a non-interactive rc).
                block=$'autoload -Uz compinit && compinit -u\nsource <(hashd completion zsh)\nsource <(wf completion zsh)\nsource <(ha completion zsh)'
                ;;
            *)
                block=$'source <(hashd completion bash)\nsource <(wf completion bash)\nsource <(ha completion bash)'
                ;;
        esac
        printf '%s\n%s\n' "$COMPLETION_MARKER" "$block" >> "$rc"
    done < <(rc_targets)
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

# Print the first semver in the input. Anchored to the FIRST match, not the
# last: tools print their own version first and may append build metadata that
# is itself a semver -- e.g. `tea --version` emits
# "Version: 0.14.1  golang: 1.26.3  go-sdk: v0.25.1", and a greedy last-match
# would wrongly read the go-sdk version as the tool version.
extract_semver() {
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
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
        tea)
            case "$machine" in
                x86_64) arch="amd64" ;;
                aarch64) arch="arm64" ;;
                *) return 1 ;;
            esac
            if [ "$os" = "macosx" ]; then
                echo "tea-${version}-darwin-${arch}"
            else
                echo "tea-${version}-linux-${arch}"
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
        tea) echo "https://dl.gitea.com/tea/${version}" ;;
        *) return 1 ;;
    esac
}

forge_checksums_name() {
    local name="$1"
    local version="$2"
    case "$name" in
        gh) echo "gh_${version}_checksums.txt" ;;
        glab|bkt|tea) echo "checksums.txt" ;;
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

warn_forge_install_failed() {
    local name="$1"
    local display="$2"
    FORGE_INSTALL_FAILURES="${FORGE_INSTALL_FAILURES} $name"
    echo ""
    echo "!! ${display} CLI (${name}) FAILED to install."
    echo "!! ${display} features will not work until this is fixed:"
    echo "!!   - re-run this installer (or scripts/install-tools.sh from a checkout), or"
    echo "!!   - place a ${name} binary at ${HASHD_TOOLS_DIR:-$HOME/.hashd/tools/bin}/${name} yourself."
    echo ""
}

install_forge_cli() {
    local name="$1"
    local display="$2"
    local version="$3"
    # hashd vendors forge CLIs into its OWN tools dir (alongside gitleaks/delta)
    # and invokes them by absolute path -- never from the system PATH -- so a
    # user upgrading or removing their own gh/tea can't shadow or break hashd.
    local bin_dir="${HASHD_TOOLS_DIR:-$HOME/.hashd/tools/bin}"
    local asset_name
    local base_url
    local checksums_name
    local forge_dir
    local asset_path
    local checksums_path
    local extract_dir
    local found_binary
    local installed_version

    # Always vendor our own pinned copy. We deliberately do NOT consult the
    # system (PATH) -- a system install is irrelevant since hashd invokes the
    # absolute bundled path. Skip the download only when OUR copy already
    # matches the pin.
    if [ -x "$bin_dir/$name" ] && [ "$(forge_binary_version "$bin_dir/$name")" = "$version" ]; then
        ok "$name $version already vendored"
        return 0
    fi

    asset_name="$(forge_asset_name "$name" "$version" "$PLATFORM" "$MACHINE")"
    base_url="$(forge_download_base_url "$name" "$version")"
    checksums_name="$(forge_checksums_name "$name" "$version")"
    forge_dir="$WORK_DIR/forge-$name"
    asset_path="$forge_dir/$asset_name"
    checksums_path="$forge_dir/$checksums_name"
    extract_dir="$forge_dir/extract"

    mkdir -p "$extract_dir"
    curl -fsSL -o "$asset_path" "$base_url/$asset_name" || return 1
    curl -fsSL -o "$checksums_path" "$base_url/$checksums_name" || return 1
    verify_forge_checksum "$asset_path" "$checksums_path" || return 1
    verified "$display CLI ($name $version)"

    case "$asset_name" in
        *.tar.gz)
            tar -xzf "$asset_path" -C "$extract_dir" || return 1
            ;;
        *.zip)
            if ! command -v unzip &>/dev/null; then
                echo "ERROR: unzip is required to extract $asset_name"
                return 1
            fi
            unzip -q "$asset_path" -d "$extract_dir" || return 1
            ;;
        tea-*)
            install -m 755 "$asset_path" "$extract_dir/$name" || return 1
            ;;
        *)
            echo "ERROR: Unsupported forge CLI archive: $asset_name"
            return 1
            ;;
    esac

    found_binary="$(find "$extract_dir" -name "$name" -type f -perm -u+x | head -1)"
    if [ -z "$found_binary" ]; then
        found_binary="$(find "$extract_dir" -name "$name" -type f | head -1)"
    fi
    if [ -z "$found_binary" ]; then
        echo "ERROR: Could not find $name inside $asset_name"
        return 1
    fi

    mkdir -p "$bin_dir"
    install -m 755 "$found_binary" "$bin_dir/$name"
    installed_version="$("$bin_dir/$name" --version 2>/dev/null | extract_semver || true)"
    if [ "$installed_version" != "$version" ]; then
        echo "ERROR: Installed $name but version check returned '${installed_version:-unknown}', expected $version"
        return 1
    fi
    ok "$name $version" "$bin_dir/$name"
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

printf '%shashd installer%s  %s%s (%s)%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$PLATFORM" "$MACHINE" "$C_RESET"

# --- Resolve the Python toolchain ---
#
# Fast path: a healthy existing Python 3.11+ with a working pipx -> use pipx.
# Otherwise (no Python, or a modern externally-managed interpreter where
# `pip install --user pipx` would hit PEP-668) -> bootstrap uv, which provides
# both a Python 3.11+ runtime and the install mechanism. One curl, no root.
step "Resolving Python toolchain"

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
            break
        fi
    fi
done

INSTALL_VIA=""
if python_pipx_healthy; then
    INSTALL_VIA="pipx"
    ok "Python $PYTHON_VERSION + pipx" "$PYTHON"
elif [ -n "$PYTHON" ] && command -v uv &>/dev/null; then
    # Python present but pipx missing. uv is already here, so prefer it over
    # the pip -> pipx -> PEP-668 gauntlet.
    INSTALL_VIA="uv"
    note "Python $PYTHON_VERSION found; pipx missing -- using uv"
    bootstrap_uv
elif [ -n "$PYTHON" ] && ! pip_pipx_install_blocked; then
    # Python present, pip can install user packages: bootstrap pipx the classic
    # way and keep the healthy toolchain path.
    note "Python $PYTHON_VERSION found; installing pipx"
    if ! "$PYTHON" -m pip --version &>/dev/null; then
        "$PYTHON" -m ensurepip --user 2>/dev/null || true
    fi
    if "$PYTHON" -m pip install --user pipx 2>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        pipx ensurepath 2>/dev/null || "$PYTHON" -m pipx ensurepath 2>/dev/null || true
        INSTALL_VIA="pipx"
        ok "pipx" "$(pipx --version 2>/dev/null || echo installed)"
    else
        # pip surprised us; fall back to uv rather than hard-error.
        note "pip could not install pipx -- using uv"
        INSTALL_VIA="uv"
        bootstrap_uv
    fi
else
    # No usable Python, or a modern externally-managed interpreter that refuses
    # `pip install --user`. This is the fresh-Arch / Homebrew-Python case the
    # old installer hard-errored on. uv provides Python 3.11+ itself.
    if [ -n "$PYTHON" ]; then
        note "Python $PYTHON_VERSION is externally managed (PEP 668) -- using uv"
    else
        note "No Python 3.11+ found -- uv will provide one"
    fi
    INSTALL_VIA="uv"
    bootstrap_uv
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Find latest release ---
step "Finding latest release"

# Resolve the latest tag WITHOUT api.github.com. github.com/<repo>/releases/latest
# is a web/CDN 302 redirect to /releases/tag/<tag> -- no 60/hr unauthenticated
# cap, the cap that broke fresh-box installs (no `gh` yet, so unauthenticated).
RELEASE_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null || true)"
RELEASE_TAG=""
case "$RELEASE_URL" in
    */releases/tag/*) RELEASE_TAG="${RELEASE_URL##*/releases/tag/}" ;;
esac

if [ -z "$RELEASE_TAG" ]; then
    die "No hashd release found" \
        "install.release_lookup" \
        "Could not read the latest release from github.com/$REPO.\nThis usually means no network access or GitHub is unreachable." \
        "Check connectivity, then re-run: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash" \
        "Or browse releases manually: https://github.com/$REPO/releases"
fi

ok "Latest release" "$RELEASE_TAG"

# --- Resolve wheel names (downloaded via direct release-asset CDN URLs) ---
# Wheels use abi3 stable ABI (cp311-abi3): works with any Python 3.11+. If the
# minimum Python changes, update this tag AND pyproject.toml requires-python.
# macOS ships one universal2 wheel; Linux is arch-tagged. Names are constructed
# from the version + platform so downloads use direct CDN URLs (no GitHub API).
ABI_TAG="cp311-abi3"
VERSION="${RELEASE_TAG#v}"
if [ "$PLATFORM" = "macosx" ]; then
    WHEEL_PLATFORM="macosx_10_9_universal2"
else
    WHEEL_PLATFORM="${PLATFORM}_${MACHINE}"
fi

WHEEL="hashd-${VERSION}-${ABI_TAG}-${WHEEL_PLATFORM}.whl"
BOT_WHEEL="hashd_bot_telegram-${VERSION}-py3-none-any.whl"
FIGMA_WHEEL="hashd_connector_figma-${VERSION}-py3-none-any.whl"
GITHUB_CONNECTOR_WHEEL="hashd_connector_github-${VERSION}-py3-none-any.whl"
JIRA_WHEEL="hashd_connector_jira-${VERSION}-py3-none-any.whl"
TUI_WHEEL="hashd_tui-${VERSION}-py3-none-any.whl"
CLIENT_WHEEL="hashd_client-${VERSION}-py3-none-any.whl"

# Download via direct release-asset CDN URLs -- no api.github.com, so immune to
# the unauthenticated 60/hr limit that fresh boxes (no `gh` yet) used to hit.
#
# An interactive terminal gets a per-wheel progress bar -- the hashd wheel is
# ~170MB and otherwise downloads in total silence (looks hung). A non-TTY run
# (CI / piped logs) stays quiet but still surfaces curl's error (-sS). --retry
# absorbs a transient CDN blip on any single wheel; without it one failed fetch
# aborts the whole install. No --max-time: the hashd wheel is large and must not
# be cut off mid-download.
step "Downloading wheels"
if [ -t 2 ]; then
    _curl_dl=(--progress-bar)
else
    _curl_dl=(-sS)
fi
DL_BASE="https://github.com/$REPO/releases/download/$RELEASE_TAG"
for _wheel in "$WHEEL" "$CLIENT_WHEEL" "$BOT_WHEEL" "$FIGMA_WHEEL" "$GITHUB_CONNECTOR_WHEEL" "$JIRA_WHEEL" "$TUI_WHEEL"; do
    printf '  %s\n' "$_wheel"
    if ! curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 \
            "${_curl_dl[@]}" -o "$WORK_DIR/$_wheel" "$DL_BASE/$_wheel"; then
        die "Could not download $_wheel" \
            "install.wheel_download" \
            "Failed to download $_wheel from the $RELEASE_TAG release.\nThis is a direct CDN download (no GitHub API), so it usually means no network access, or no wheel was published for this platform ($PLATFORM/$MACHINE)." \
            "Check the release assets: https://github.com/$REPO/releases/tag/$RELEASE_TAG" \
            "Then re-run: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
    fi
done

# Resolve to absolute paths for the install step (the loop verified each download).
WHEEL="$WORK_DIR/$WHEEL"
BOT_WHEEL="$WORK_DIR/$BOT_WHEEL"
FIGMA_WHEEL="$WORK_DIR/$FIGMA_WHEEL"
GITHUB_CONNECTOR_WHEEL="$WORK_DIR/$GITHUB_CONNECTOR_WHEEL"
JIRA_WHEEL="$WORK_DIR/$JIRA_WHEEL"
TUI_WHEEL="$WORK_DIR/$TUI_WHEEL"
CLIENT_WHEEL="$WORK_DIR/$CLIENT_WHEEL"

ok "Downloaded wheels" "CLI + server + client SDK + bot + figma/github/jira connectors + TUI"

# --- Install forge CLIs ---
# All supported forge CLIs, always: prebuilt binaries, SHA-256 verified, no prompts.
step "Installing forge CLIs (gh, glab, bkt, tea)"
# Forge CLI install failures are loud but never abort the install: a
# project only needs its own forge's CLI, so a glab asset outage must
# not block a GitHub user. hashd resolves these from its tools dir
# ONLY -- the failed feature stays broken until one of the fixes below
# is applied, and `hashd doctor` reports the same state.
FORGE_INSTALL_FAILURES=""
install_forge_cli gh "GitHub" "$GH_VERSION" || warn_forge_install_failed gh "GitHub"
install_forge_cli glab "GitLab" "$GLAB_VERSION" || warn_forge_install_failed glab "GitLab"
install_forge_cli bkt "Bitbucket" "$BKT_VERSION" || warn_forge_install_failed bkt "Bitbucket"
install_forge_cli tea "Gitea" "$TEA_VERSION" || warn_forge_install_failed tea "Gitea"
if [ -n "$FORGE_INSTALL_FAILURES" ]; then
    echo "NOTE: some forge CLIs failed to install:${FORGE_INSTALL_FAILURES}. See the blocks above; \`hashd doctor\` tracks this."
fi

# --- Install hashd wheels ---
# Either pipx (healthy existing toolchain) or uv (provides Python 3.11+ and the
# install mechanism on a bare box). Both land entry points in ~/.local/bin.
if [ "$INSTALL_VIA" = "uv" ]; then
    install_via_uv
else
    install_via_pipx
fi
ok "hashd installed"

OPS_ROOT="${HASHD_OPS_ROOT:-$HOME/.hashd}"
mkdir -p "$OPS_ROOT"/{projects,workstreams,worktrees,runs,locks,cache,secrets,config}
HASHD_BIN="${PIPX_BIN_DIR:-$HOME/.local/bin}/hashd"
if [ "$INSTALL_VIA" = "pipx" ]; then
    promote_pipx_binary hashd || true
    promote_pipx_binary wf || true
    promote_pipx_binary ha || true
    promote_pipx_binary hashd-server || true
fi
if [ ! -x "$HASHD_BIN" ]; then
    # uv tool install puts entry points directly in ~/.local/bin; pipx puts
    # them there via the promote step above. Resolve whatever is on PATH.
    if command -v hashd &>/dev/null; then
        HASHD_BIN="$(command -v hashd)"
    fi
fi
if [ ! -x "$HASHD_BIN" ]; then
    die "Installed hashd not found on PATH" \
        "install.hashd_missing" \
        "hashd installed but the hashd entry point is not at $HASHD_BIN and not on PATH.\nInstall method: $INSTALL_VIA." \
        "Open a new shell or run: export PATH=\"\$HOME/.local/bin:\$PATH\"" \
        "Then re-run: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
fi
bin_dir="$(dirname "$HASHD_BIN")"
ln -sf hashd "$bin_dir/wf"
ln -sf hashd "$bin_dir/ha"

# uv/pipx wire the entry-points dir onto PATH for bash, but not reliably for
# zsh -- so hashd/wf land in ~/.local/bin yet read as command-not-found in a
# fresh macOS (zsh) terminal. Persist it into the zsh rc too.
ensure_dir_on_path "$bin_dir" "# hashd bin dir (managed by hashd install scripts)"

install_completions

# --- Install external tools (gitleaks, git-delta, ...) ---
# Delegates to scripts/install-tools.sh from main -- the same script
# `hashd` auto-invokes on source checkouts when a tool is missing. One
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
#    The latent risk: if we ever ship hashd code that depends on a
#    specific tool version's output shape (say, gitleaks 9.x
#    reshuffles the JSON fields hashd parses) and later bump the
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
step "Installing external tools (gitleaks, git-delta)"
# Wire the bundled-tools dir onto PATH before the install runs, so the freshly
# dropped gitleaks/delta binaries resolve as bare commands everywhere (the
# user's shell and any subprocess), not just via hashd's tools-dir-aware code.
ensure_tools_dir_on_path
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

step "Configuring owner identity"
# hashd-server fails closed when no user is configured, so the first user -- the
# active, keyless owner (the solo default identity) -- is created before the
# server starts. This installer is non-interactive (curl | bash), so the owner is
# derived from git config, falling back to $USER@host. Idempotent: skip if any
# user already exists.
if "$HASHD_BIN" admin user list 2>/dev/null | grep -q '@'; then
    ok "Owner already configured"
else
    OWNER_NAME="$(git config --global user.name 2>/dev/null || true)"
    OWNER_EMAIL="$(git config --global user.email 2>/dev/null || true)"
    [ -n "$OWNER_EMAIL" ] || OWNER_EMAIL="${USER:-hashd}@$(hostname -s 2>/dev/null || echo localhost)"
    [ -n "$OWNER_NAME" ] || OWNER_NAME="${USER:-hashd}"
    OWNER_ERR=""
    if [ -n "$OWNER_NAME" ]; then
        OWNER_ERR="$("$HASHD_BIN" admin user add "$OWNER_EMAIL" --name "$OWNER_NAME" 2>&1)" || OWNER_ADD_FAILED=1
    else
        OWNER_ERR="$("$HASHD_BIN" admin user add "$OWNER_EMAIL" 2>&1)" || OWNER_ADD_FAILED=1
    fi
    if [ -n "${OWNER_ADD_FAILED:-}" ]; then
        # Hard-fail: hashd-server fails closed without an owner, so a swallowed
        # failure here just surfaces later as a dead server. Better to abort the
        # install loudly with the exact recovery command.
        die "could not provision the hashd owner" \
            "install.owner" \
            "hashd-server fails closed until an active owner exists, so the install is not usable without one.\n${OWNER_ERR}" \
            "Create it manually, then re-run the installer: $HASHD_BIN admin user add $OWNER_EMAIL"
    fi
    ok "Owner: $OWNER_EMAIL"
fi

step "Starting hashd services"
# `hashd restart` brings up Prefect + worker and registers the INSTALL-OWNED
# infrastructure, including the housekeeping cron, on this first pass -- it
# waits for Prefect's deployment API to accept writes before reporting success,
# so a fresh install no longer needs a warm second restart to land housekeeping.
# First attempt is quiet; on failure we retry once with output, and `set -e`
# makes a second failure abort the install with the restart diagnostic. A failed
# restart means the install-owned infrastructure did not converge -- that is a
# genuinely broken install, so we stop here rather than print a misleading
# success.
"$HASHD_BIN" restart --yes >/dev/null 2>&1 || {
    printf '%s   first restart did not converge; retrying with output...%s\n' "$C_DIM" "$C_RESET"
    "$HASHD_BIN" restart --yes
}
ok "Services started"

printf '\n%s+ Installed hashd %s%s\n\n' "${C_GREEN}${C_BOLD}" "$RELEASE_TAG" "$C_RESET"

# --- Verify with the doctor report ---
# `hashd doctor` now reads honestly: the INSTALL-OWNED checks (server, Prefect,
# housekeeping cron, bundled gitleaks + delta) must be green after a successful
# install, and the USER-SETUP gaps (git, an agent CLI, forge auth) render as a
# "Finish setup:" checklist rather than a red failure wall. doctor exits
# non-zero while setup is unfinished, so we ignore its exit here: a fresh box
# WILL have those user-setup steps outstanding, and that is expected, not a
# broken install (a broken install already aborted at the restart step above).
step "Running hashd doctor"
echo ""
"$HASHD_BIN" doctor || true
echo ""

# --- Agent on-ramp ---
# hashd needs git + one authenticated agent CLI. Agents are npm-installed, so
# Node is the agent's prerequisite, not hashd's. Print the ONE OS-correct path.
NODE_HINT="$(node_install_hint)"
printf '%sAdd an AI agent%s -- hashd needs one authenticated agent CLI:\n' "$C_BOLD" "$C_RESET"
step "Install Node.js 20+:  $NODE_HINT"
step "Install Claude Code:  npm i -g @anthropic-ai/claude-code"
step "Authenticate:         claude login"
echo ""

# --- Forge auth ---
printf '%sAuthenticate a forge%s (only the one you use):\n' "$C_BOLD" "$C_RESET"
note "GitHub:    gh auth login"
note "GitLab:    glab auth login"
note "Bitbucket: bkt auth login --kind cloud --web"
note "Gitea:     tea login add --name work --url https://git.example.com --token \$TOKEN"
echo ""

# The install always writes PATH + completions into your shell rc, so the
# current shell needs a reload before hashd, its completions, and PATH are live.
# We can't source your interactive shell from here (a child process can't mutate
# its parent's environment), so tell you exactly what to run.
case "${SHELL:-}" in
    *zsh*) RELOAD_RC="$HOME/.zshrc" ;;
    *bash*) RELOAD_RC="$HOME/.bashrc" ;;
    *) [ "${PLATFORM:-}" = "macosx" ] && RELOAD_RC="$HOME/.zshrc" || RELOAD_RC="" ;;
esac
if [ -n "$RELOAD_RC" ]; then
    printf '%sReload your shell to finish:%s source %s   (or open a new terminal)\n' "$C_BOLD" "$C_RESET" "$RELOAD_RC"
else
    printf '%sReload your shell to finish:%s open a new terminal so PATH + completions take effect\n' "$C_BOLD" "$C_RESET"
fi
echo ""

# --- One inviting next action ---
printf '%sNext:%s register your first repo\n' "$C_BOLD" "$C_RESET"
printf '  %s->%s hashd project add /path/to/your/repo\n' "$C_BLUE" "$C_RESET"
echo ""
