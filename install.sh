#!/bin/bash
# hashd installer
# Usage: curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
# Intended for packaged wheel installs/upgrades.
# This script should be safe to re-run; install, migration, and restart work
# are expected to be idempotent.
# Shared, read-only preflight for source and packaged installers.

# Resolve existing symlinks and missing trailing components without GNU readlink -f.
hashd_install_path() (
    local path="$1" parent leaf target depth="${2:-0}"
    case "$path" in *$'\n'*) echo 'Error: installation paths must not contain newlines.' >&2; return 1 ;; esac
    [ "$depth" -lt 40 ] || return 1
    case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
    [ "$path" != / ] || { printf '/\n'; return; }
    path="${path%/}"
    parent="$(dirname "$path")"
    leaf="$(basename "$path")"
    parent="$(hashd_install_path "$parent" "$((depth + 1))")" || return 1
    case "$leaf" in
        .) printf '%s\n' "$parent"; return ;;
        ..) dirname "$parent"; return ;;
    esac
    path="${parent%/}/$leaf"
    if [ -L "$path" ]; then
        target="$(readlink "$path")" || return 1
        case "$target" in /*) ;; *) target="$parent/$target" ;; esac
        hashd_install_path "$target" "$((depth + 1))"
    else
        printf '%s\n' "$path"
    fi
)

# Old installs have no receipt. Recognize the same source/package layouts as
# the CLI bootstrap; an arbitrary executable or dangling link is not proof.
hashd_install_legacy_root() {
    local launcher="$1" target="$1" root data dir link depth=0
    # Source inference checks each launch location before following its symlink,
    # including a cleaned checkout whose bin/hashd has not been rebuilt yet.
    while [ "$depth" -lt 20 ]; do
        dir="$(hashd_install_path "$(dirname "$target")")" || return 1
        for root in "$(dirname "$dir")" "$dir"; do
            if [ -f "$root/server/go.mod" ] &&
                grep -Eq '^[[:space:]]*module github\.com/codr1/hashd/server[[:space:]]*$' "$root/server/go.mod"; then
                printf '%s\n' "$root"
                return
            fi
        done
        [ -L "$target" ] || break
        link="$(readlink "$target")" || return 1
        case "$link" in /*) target="$link" ;; *) target="$dir/$link" ;; esac
        depth=$((depth + 1))
    done
    target="$(hashd_install_path "$launcher")" || return 1
    [ -f "$target" ] || return 1
    root="$(dirname "$(dirname "$target")")"
    for data in "$root"/lib/python*/site-packages/hashd_data \
        "$root"/lib64/python*/site-packages/hashd_data "$root"/Lib/site-packages/hashd_data; do
        if [ -d "$data/prompts" ] && [ -d "$data/templates" ] && [ -d "$data/schemas" ]; then
            hashd_install_path "$HOME/.hashd"
            return
        fi
    done
    return 1
}

hashd_install_receipt_root() {
    local launcher="$1" receipt version target root extra resolved
    receipt="$(dirname "$launcher")/.hashd-install"
    [ -e "$receipt" ] || [ -L "$receipt" ] || return 1
    [ -f "$receipt" ] && [ ! -L "$receipt" ] || return 2
    {
        IFS= read -r version && IFS= read -r target && IFS= read -r root &&
            ! IFS= read -r extra && [ -z "$extra" ]
    } < "$receipt" || return 2
    [ "$version" = hashd-install-v1 ] || return 2
    case "$root" in /*) ;; *) return 2 ;; esac
    resolved="$(hashd_install_path "$launcher")" || return 2
    [ "$target" = "$resolved" ] || return 1
    hashd_install_path "$root" || return 2
}

# With no override, retain a recorded custom root on an ordinary update. A
# different source checkout still proposes its own root and requires consent.
hashd_install_default_root() {
    local preferred="$1" default="$2" launcher legacy recorded
    while IFS= read -r launcher; do
        legacy="$(hashd_install_legacy_root "$launcher")" || legacy=""
        if [ "$legacy" = "$default" ] && recorded="$(hashd_install_receipt_root "$launcher")"; then
            printf '%s\n' "$recorded"
            return
        fi
    done < <(hashd_install_launchers "$preferred")
    printf '%s\n' "$default"
}

hashd_install_check() {
    local launcher="$1" proposed="$2" replacement="$3" proposed_binary="$4"
    local target current rc
    [ -e "$launcher" ] || [ -L "$launcher" ] || return 0
    target="$(hashd_install_path "$launcher")" || target="unresolved: $launcher"
    if current="$(hashd_install_receipt_root "$launcher")"; then
        :
    else
        rc=$?
        if [ "$rc" = 1 ]; then
            current="$(hashd_install_legacy_root "$launcher")" || current=""
        fi
        [ -n "$current" ] || current="unknown (installation could not be identified)"
    fi
    [ "$current" != "$proposed" ] || return 0
    {
        if [ "$replacement" = 1 ]; then
            printf 'Replacing a competing hashd installation (--replace-install).\n'
        else
            printf 'Error: another hashd installation is already configured.\n'
        fi
        printf '\n  Existing command: %s\n  Existing executable: %s\n  Existing operations root: %s\n' "$launcher" "$target" "$current"
        printf '\n  Proposed executable: %s\n  Proposed operations root: %s\n\n' "$proposed_binary" "$proposed"
        printf '%s\n' \
            'Continuing would replace the installation used by the hashd command' \
            'and restart services against the proposed installation.' \
            'Existing data is not deleted or moved. Its projects, settings and' \
            'authentication do not carry over automatically. A fresh installation' \
            'uses solo mode; do not assume the existing team-mode authentication remains.'
        if [ "$replacement" != 1 ]; then
            printf '\n%s\n' \
                'No installation changes have been made.' \
                'To update normally, use the existing installation and operations root.' \
                'To explicitly replace it, rerun this installer with --replace-install.'
        fi
    } >&2
    [ "$replacement" = 1 ]
}

# Check every launcher the installers may replace, plus the active PATH entry.
# Nothing here executes the old binary, touches its data, or contacts services.
hashd_install_launchers() {
    local launcher seen=$'\n'
    for launcher in "${1:-}" "$HOME/.local/bin/hashd" "${PIPX_BIN_DIR:-$HOME/.local/bin}/hashd" \
        "${UV_TOOL_BIN_DIR:-$HOME/.local/bin}/hashd" "$(type -P hashd || true)"; do
        [ -n "$launcher" ] || continue
        case "$seen" in *$'\n'"$launcher"$'\n'*) continue ;; esac
        seen+="$launcher"$'\n'
        printf '%s\n' "$launcher"
    done
}

hashd_install_preflight() {
    local proposed="$1" replacement="$2" proposed_binary="$3" launcher
    proposed="$(hashd_install_path "$proposed")" || {
        echo 'Error: cannot resolve the proposed operations root; no installation changes made.' >&2
        return 1
    }
    while IFS= read -r launcher; do
        hashd_install_check "$launcher" "$proposed" "$replacement" "$proposed_binary" || return 1
    done < <(hashd_install_launchers)
}

# Bind the selected root to the installed executable, not to a release version.
# A receipt from a replaced launcher cannot authorize an unrelated installation.
hashd_install_record() (
    local launcher="$1" root="$2" target receipt staged
    target="$(hashd_install_path "$launcher")" || return 1
    root="$(hashd_install_path "$root")" || return 1
    case "$target$root" in *$'\n'*) echo 'Error: installation paths must not contain newlines.' >&2; return 1 ;; esac
    receipt="$(dirname "$launcher")/.hashd-install"
    [ ! -d "$receipt" ] || { echo "Error: $receipt is a directory, not an installation receipt." >&2; return 1; }
    staged="$(mktemp "${receipt}.XXXXXX")" || return 1
    trap 'rm -f "$staged"' EXIT
    printf 'hashd-install-v1\n%s\n%s\n' "$target" "$root" > "$staged" || return 1
    mv -f "$staged" "$receipt"
)

REPO="codr1/hashd-code"
COMPLETION_MARKER="# hashd/wf completions (managed by hashd install scripts -- drop after v1.0 once everyone has migrated)"

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
    HASHD_BIN="${UV_TOOL_BIN_DIR:-$HOME/.local/bin}/hashd"
    step "Installing hashd via uv (Python 3.11+ managed by uv)"
    "$UV_BIN" tool install --force --python 3.11 \
        --with "$CLIENT_WHEEL" \
        --with "$BOT_WHEEL" \
        --with "$FIGMA_WHEEL" \
        --with "$GITHUB_CONNECTOR_WHEEL" \
        --with "$JIRA_WHEEL" \
        --with "$CONFLUENCE_WHEEL" \
        --with "$AZURE_WHEEL" \
        --with "$CLICKUP_WHEEL" \
        --with "$TUI_WHEEL" \
        "$WHEEL"
    # uv tool installs land in ~/.local/bin by default; make sure it's wired up.
    "$UV_BIN" tool update-shell >/dev/null 2>&1 || true
    export PATH="$HOME/.local/bin:$PATH"
}

# install_via_pipx: the classic healthy-toolchain path. Unchanged behavior:
# pipx owns the primary wheel, runpip injects the extras.
install_via_pipx() {
    HASHD_BIN="${PIPX_BIN_DIR:-$HOME/.local/bin}/hashd"
    step "Installing hashd via pipx"
    pipx install --force --pip-args "--find-links $WORK_DIR" "$WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$CLIENT_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$BOT_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$FIGMA_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$GITHUB_CONNECTOR_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$JIRA_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$CONFLUENCE_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$AZURE_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
    pipx runpip hashd install --upgrade "$CLICKUP_WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'
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

# git_install_hint: the ONE OS-correct command to install git. git is a system
# prerequisite hashd shells out to for every project op (worktrees, commits,
# merges) -- the installer checks for it but, like a C library or coreutils,
# never bundles or installs it. Detect the platform's package manager so the
# suggestion is a single copy-paste line, not a multi-distro menu.
git_install_hint() {
    if [ "$PLATFORM" = "macosx" ]; then
        echo "xcode-select --install"
    elif command -v apt-get &>/dev/null; then
        echo "sudo apt-get install -y git"
    elif command -v dnf &>/dev/null; then
        echo "sudo dnf install -y git"
    elif command -v pacman &>/dev/null; then
        echo "sudo pacman -S --noconfirm git"
    elif command -v zypper &>/dev/null; then
        echo "sudo zypper install -y git"
    elif command -v apk &>/dev/null; then
        echo "sudo apk add git"
    else
        echo "install git with your system package manager"
    fi
}

# rc_targets: the shell rc files the installer manages (PATH + completions).
# Always ~/.bashrc (bash). macOS Terminal runs zsh and never sources ~/.bashrc,
# so include ~/.zshrc on macOS -- and on Linux too when the login shell is zsh.
# Without this the freshly installed hashd/wf entry points and the bundled tools
# never land on the zsh PATH, and `hashd`/`wf` read as command-not-found.
# rc_targets: every file that should carry the PATH snippet.
#
# ~/.bashrc covers interactive shells, and most distro bashrc files return
# early for non-interactive ones -- so a plain `ssh host 'hashd ...'` sees
# none of it. ~/.profile / ~/.zprofile cover LOGIN shells, which is what
# `ssh host bash -lc '...'` and desktop sessions get. Between them the
# remaining gap is a non-login non-interactive shell, which no file can
# reach portably; the closing note tells the operator what to do there
# instead of pretending it is covered.
# bash_login_profile names the file a login bash actually reads: the first
# existing of ~/.bash_profile, ~/.bash_login, ~/.profile -- bash consults one
# and stops. Writing ~/.profile unconditionally misses any box that has a
# ~/.bash_profile which does not source it.
bash_login_profile() {
    for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    printf '%s\n' "$HOME/.profile"
}

rc_targets() {
    printf '%s\n' "$HOME/.bashrc"
    printf '%s\n' "$(bash_login_profile)"
    case "${SHELL:-}" in
        *zsh*) printf '%s\n' "$HOME/.zshrc"; printf '%s\n' "$HOME/.zprofile"; return ;;
    esac
    if [ "${PLATFORM:-}" = "macosx" ]; then
        printf '%s\n' "$HOME/.zshrc"
        printf '%s\n' "$HOME/.zprofile"
    fi
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
        # Guarded rather than a bare export: the snippet now lives in both
        # an rc and a profile, and an interactive login shell sources both.
        printf '%s\ncase ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' \
            "$marker" "$dir" "$dir" >> "$rc"
    done < <(rc_targets)
}

# ensure_tools_dir_on_path: persist the bundled-tools dir (~/.hashd/tools/bin,
# honoring $HASHD_TOOLS_DIR) onto PATH. install-tools.sh drops gitleaks,
# git-delta and ripgrep there; without this they resolve for hashd's tools-dir-aware code
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
# Each source line is guarded by `command -v` so a login shell never errors when
# the binary is transiently absent (mid-upgrade, cleaned build, moved checkout):
# the completion is skipped, not shouted about on every prompt.
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
            -e '^[[:space:]]*command -v (hashd|wf|ha) >/dev/null 2>&1 && source[[:space:]]+<\((hashd|wf|ha) completion (bash|zsh)\)[[:space:]]*$' \
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
                block=$'autoload -Uz compinit && compinit -u\ncommand -v hashd >/dev/null 2>&1 && source <(hashd completion zsh)\ncommand -v wf >/dev/null 2>&1 && source <(wf completion zsh)\ncommand -v ha >/dev/null 2>&1 && source <(ha completion zsh)'
                ;;
            *)
                block=$'command -v hashd >/dev/null 2>&1 && source <(hashd completion bash)\ncommand -v wf >/dev/null 2>&1 && source <(wf completion bash)\ncommand -v ha >/dev/null 2>&1 && source <(ha completion bash)'
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

warn_external_tools() {
    echo "WARN: external tool install skipped ($1)."
    echo "      This step vendors gitleaks, git-delta, ripgrep, and the forge CLIs (gh, glab, bkt, tea)."
    echo "      Without them: the merge secret-scan and your forge's features will not work."
    echo "      Fix: re-run this installer once the fetch succeeds."
}

# setup.sh and installer tests source definitions without running installation.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0
fi

set -e
REPLACE_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --replace-install) REPLACE_INSTALL=1 ;;
        -y|--yes) ;; # Already non-interactive; never authorizes replacement.
        *) echo "Usage: install.sh [--replace-install]" >&2; exit 1 ;;
    esac
done

# Refuse before dependency installation, downloads, migrations, or service changes.
OPS_ROOT="${HASHD_OPS_ROOT:-$(hashd_install_default_root '' "$(hashd_install_path "$HOME/.hashd")")}"
OPS_ROOT="$(hashd_install_path "$OPS_ROOT")"
export HASHD_OPS_ROOT="$OPS_ROOT"
hashd_install_preflight "$OPS_ROOT" "$REPLACE_INSTALL" 'packaged hashd (uv/pipx managed)'

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

# --- Preflight: git is a hard prerequisite ---
#
# hashd shells out to the system git for every project op (worktrees, commits,
# merges). Unlike the specialty tools this installer vendors (gitleaks,
# git-delta, the forge CLIs), git is a base system dependency -- like a C
# library -- that hashd requires but never installs. Fail here, before any
# download or toolchain work, with the one command that fixes it.
if ! command -v git &>/dev/null; then
    die "git is required but was not found on PATH" \
        "install.preflight" \
        "hashd drives every project through git -- creating worktrees, committing micro-commits, and merging -- by shelling out to your system git.\nIt is a base system prerequisite the installer checks for but does not provide." \
        "Install git, then re-run this installer:  $(git_install_hint)"
fi

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
# The core wheel is a pure-Python carrier for per-platform Go binaries:
# python tag py3-none, platform tag set explicitly by the release build
# (HASHD_WHEEL_PLAT). macOS ships an arm64 wheel (Apple Silicon; the Go
# binaries are single-arch). Names are constructed from the version +
# platform so downloads use direct CDN URLs (no GitHub API).
ABI_TAG="py3-none"
VERSION="${RELEASE_TAG#v}"
if [ "$PLATFORM" = "macosx" ]; then
    WHEEL_PLATFORM="macosx_11_0_arm64"
else
    WHEEL_PLATFORM="${PLATFORM}_${MACHINE}"
fi

WHEEL="hashd-${VERSION}-${ABI_TAG}-${WHEEL_PLATFORM}.whl"
BOT_WHEEL="hashd_bot_telegram-${VERSION}-py3-none-any.whl"
FIGMA_WHEEL="hashd_connector_figma-${VERSION}-py3-none-any.whl"
GITHUB_CONNECTOR_WHEEL="hashd_connector_github-${VERSION}-py3-none-any.whl"
JIRA_WHEEL="hashd_connector_jira-${VERSION}-py3-none-any.whl"
CONFLUENCE_WHEEL="hashd_connector_confluence-${VERSION}-py3-none-any.whl"
AZURE_WHEEL="hashd_connector_azure_devops-${VERSION}-py3-none-any.whl"
CLICKUP_WHEEL="hashd_connector_clickup-${VERSION}-py3-none-any.whl"
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
for _wheel in "$WHEEL" "$CLIENT_WHEEL" "$BOT_WHEEL" "$FIGMA_WHEEL" "$GITHUB_CONNECTOR_WHEEL" "$JIRA_WHEEL" "$CONFLUENCE_WHEEL" "$AZURE_WHEEL" "$CLICKUP_WHEEL" "$TUI_WHEEL"; do
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
CONFLUENCE_WHEEL="$WORK_DIR/$CONFLUENCE_WHEEL"
AZURE_WHEEL="$WORK_DIR/$AZURE_WHEEL"
CLICKUP_WHEEL="$WORK_DIR/$CLICKUP_WHEEL"
TUI_WHEEL="$WORK_DIR/$TUI_WHEEL"
CLIENT_WHEEL="$WORK_DIR/$CLIENT_WHEEL"

ok "Downloaded wheels" "CLI + server + client SDK + bot + figma/github/jira/confluence/azure/clickup connectors + TUI"

# Forge CLIs (gh, glab, bkt, tea) are installed further down by
# scripts/install-tools.sh, which owns every vendored tool and its pin.
# Nothing between here and there needs one.

# --- Install hashd wheels ---
# Either pipx (healthy existing toolchain) or uv (provides Python 3.11+ and the
# install mechanism on a bare box). Both land entry points in ~/.local/bin.
if [ "$INSTALL_VIA" = "uv" ]; then
    install_via_uv
else
    install_via_pipx
fi
ok "hashd installed"

mkdir -p "$OPS_ROOT"/{projects,workstreams,worktrees,runs,locks,cache,secrets,config}
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
hashd_install_record "$HASHD_BIN" "$OPS_ROOT"
ln -sf hashd "$bin_dir/wf"
ln -sf hashd "$bin_dir/ha"

# uv/pipx wire the entry-points dir onto PATH for bash, but not reliably for
# zsh -- so hashd/wf land in ~/.local/bin yet read as command-not-found in a
# fresh macOS (zsh) terminal. Persist it into the zsh rc too.
ensure_dir_on_path "$bin_dir" "# hashd bin dir (managed by hashd install scripts)"

install_completions

# --- Install external tools (gitleaks, git-delta, ...) ---
# Use the selected release's installer and npm lock, not moving main. Browser
# binaries remain install-time upstream downloads, never wheel payloads.
TOOLS_BASE_URL="https://raw.githubusercontent.com/$REPO/$RELEASE_TAG"
TOOLS_SCRIPT_URL="$TOOLS_BASE_URL/scripts/install-tools.sh"
TOOLS_OS="$PLATFORM"
if [ "$TOOLS_OS" = "macosx" ]; then
    TOOLS_OS="darwin"
fi
TOOLS_ARCH="$MACHINE"
case "$TOOLS_ARCH" in
    x86_64) TOOLS_ARCH="amd64" ;;
    aarch64) TOOLS_ARCH="arm64" ;;
esac
step "Installing external tools (gitleaks, git-delta, ripgrep, forge CLIs, browser)"
# Wire the bundled-tools dir onto PATH before the install runs, so the freshly
# dropped gitleaks/delta binaries resolve as bare commands everywhere (the
# user's shell and any subprocess), not just via hashd's tools-dir-aware code.
ensure_tools_dir_on_path
mkdir -p "$WORK_DIR/scripts" "$WORK_DIR/vendor/playwright"
if curl --fail --silent --location \
    --retry 3 --retry-delay 2 \
    --connect-timeout 10 --max-time 60 \
    "$TOOLS_SCRIPT_URL" -o "$WORK_DIR/scripts/install-tools.sh" 2>/dev/null; then
    for browser_lock in package.json package-lock.json; do
        if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
            "$TOOLS_BASE_URL/vendor/playwright/$browser_lock" \
            -o "$WORK_DIR/vendor/playwright/$browser_lock"; then
            warn_external_tools "could not download browser lock $browser_lock; browser installation will report unavailable"
        fi
    done
    if ! HASHD_TOOLS_OS="$TOOLS_OS" HASHD_TOOLS_ARCH="$TOOLS_ARCH" bash "$WORK_DIR/scripts/install-tools.sh"; then
        warn_external_tools "installer script failed"
    fi
else
    warn_external_tools "could not download installer script"
fi

step "Migrating local databases"
# Before anything opens a database. A checkout upgraded across a schema bump
# has databases at the old version, and every command that opens one --
# starting with the owner check below -- fails closed on the mismatch. Its
# advice then points at a command that cannot run until this has, so the
# install dies with the real fix buried inside a nested error.
if "$HASHD_BIN" internal migrate-dbs >/dev/null 2>&1; then
    ok "Databases migrated"
else
    # Non-fatal: a fresh install has nothing to migrate, and a genuine
    # failure surfaces with its own diagnostic at the next open.
    ok "No databases to migrate"
fi

step "Configuring owner identity"
# hashd-server fails closed when no user is configured, so the first user -- the
# active, keyless owner (the solo default identity) -- is created before the
# server starts. This installer is non-interactive (curl | bash), so the owner is
# derived from git config, falling back to $USER@host. Idempotent: skip if any
# user already exists.
#
# A machine paired to a REMOTE server has no local server to own: its ops dir
# is inert, the owner would be created in a database nothing reads, and a
# failure here would abort an install that is otherwise complete. Skip it and
# say why.
if [ -n "${HASHD_SERVER_URL:-}" ] && ! printf '%s' "$HASHD_SERVER_URL" | grep -qE '://(127\.0\.0\.1|localhost|\[::1\])'; then
    ok "Paired to a remote server ($HASHD_SERVER_URL) -- no local owner needed"
elif "$HASHD_BIN" admin user list 2>/dev/null | grep -q '@'; then
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
        # A schema-version mismatch is a local checkpoint lagging the build,
        # not a missing owner -- surface its fix at the top rather than
        # leaving it nested inside the inner error, and never advise
        # "run this on the server host" to a client-only machine.
        if printf '%s' "$OWNER_ERR" | grep -q 'schema version mismatch'; then
            die "the local databases are behind this build" \
                "install.schema_behind" \
                "Owner provisioning opened a database at an older schema version than this build expects.\n${OWNER_ERR}" \
                "Migrate them, then re-run the installer: $HASHD_BIN internal migrate-dbs"
        fi
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
#
# Two explicit controls, and deliberately neither --yes nor --force:
#   --in-place-upgrade  says this restart stands in for the installer's steps.
#                       A packaged install never trips the manual-upgrade gate,
#                       but this flag is also what tells a refusal that it
#                       leaves an INCOMPLETE UPGRADE -- by this line the new
#                       binaries are in place and migrate-dbs has run -- so the
#                       refusal names the command that finishes it.
#   --reclaim-port      authorizes killing an unrecognized process that still
#                       holds the hashd-server port as the server starts. The
#                       installer runs headless, where the start path refuses
#                       rather than kills without it.
# Without --force the restart puts a restart hold in force and WAITS, with no
# limit of its own, until running work reaches a stopping point: an unattended
# install interrupts nothing. The wait prints progress the whole time, so the
# output is streamed rather than captured -- a captured wait would look like a
# frozen install for as long as a merge or an agent stage takes.
#
# The first attempt's output is also kept, because two different failures come
# out of this line and only one of them is worth a retry:
#   - a refusal: the restart hold could not be put in force
#     (restart.hold_unavailable), or --force was asked for without a terminal
#     (restart.force_headless). Not a convergence failure; re-running the
#     identical command refuses again. Print nothing more (the refusal is
#     already on screen and names the command that finishes this install) and
#     stop. Detected on the Diagnostic's source tag rather than its prose.
#   - anything else. Retry once with output, exactly as before.
#
# A long wait is neither: the command has not exited, so there is nothing to
# retry. Both attempts read stdin from /dev/null so the restart is headless on
# either invocation style.
restart_log="$(mktemp)"
set +e
"$HASHD_BIN" restart --in-place-upgrade --reclaim-port </dev/null 2>&1 | tee "$restart_log"
restart_status=${PIPESTATUS[0]}
set -e
if [ "$restart_status" -ne 0 ]; then
    if grep -q 'restart\.hold_unavailable\|restart\.force_headless' "$restart_log"; then
        rm -f "$restart_log"
        exit 1
    fi
    printf '%s   first restart did not converge; retrying with output...%s\n' "$C_DIM" "$C_RESET"
    rm -f "$restart_log"
    "$HASHD_BIN" restart --in-place-upgrade --reclaim-port </dev/null
fi
rm -f "$restart_log"
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
    printf '%sDriving this box over SSH or from a script?%s A non-interactive shell reads none of\n' "$C_BOLD" "$C_RESET"
    printf '  those files, so use a login shell or the full path:\n'
    printf '    ssh HOST bash -lc %shashd status%s      # login shell, picks up PATH\n' "'" "'"
    printf '    ssh HOST %s status                   # or just call it directly\n' "$HASHD_BIN"
else
    printf '%sReload your shell to finish:%s open a new terminal so PATH + completions take effect\n' "$C_BOLD" "$C_RESET"
fi
echo ""

# --- One inviting next action ---
printf '%sReady to work?%s Run hashd for your next step, or hashd watch for the TUI.\n' "$C_BOLD" "$C_RESET"
printf '  Add a project: hashd project add /path/to/your/repo\n'
printf '  Joining a team? https://github.com/codr1/hashd-code/blob/main/docs/REMOTE.md\n'
echo ""
