#!/usr/bin/env bash
# scripts/install-tools.sh -- install external binaries hashd depends on.
#
# Single source of truth for external tool installation. Consumed by:
#   - `task tools:install` (source developers, directly)
#   - `dist/install.sh`    (wheel users, fetched over HTTPS at install time)
#
# Tools land in ${HASHD_TOOLS_DIR:-~/.hashd/tools/bin} so both flows
# populate the bundled-tools location used by server-side checks and
# client-side TUI rendering.
#
# Idempotent: if the installed binary reports the expected version,
# re-runs are a no-op. Stale installs (wrong version) are replaced.
#
# Scope: released hashd platforms: Linux x86_64/aarch64 and macOS arm64.
# Windows and Intel macOS are not supported.

set -euo pipefail

TOOLS_DIR="${HASHD_TOOLS_DIR:-$HOME/.hashd/tools/bin}"
mkdir -p "$TOOLS_DIR"

# ---------------------------------------------------------------------
# Platform detection (OS only; arch mapping is per-tool below because
# different tools name their assets differently: gitleaks uses x64,
# git-delta uses Rust target triples, etc.).
#
# dist/install.sh passes HASHD_TOOLS_OS/HASHD_TOOLS_ARCH from the same
# runtime platform it uses to select the wheel. Source checkouts use uname.
# ---------------------------------------------------------------------
DETECTED_OS="${HASHD_TOOLS_OS:-$(uname -s)}"
case "$DETECTED_OS" in
    Linux|linux)  OS=linux ;;
    Darwin|darwin|macosx) OS=darwin ;;
    *)
        echo "install-tools: unsupported OS: $DETECTED_OS" >&2
        exit 1
        ;;
esac

RAW_ARCH="${HASHD_TOOLS_ARCH:-$(uname -m)}"

# Pinned tool versions, hoisted to top level so scripts/check-external-assets.sh
# can read them as the single source of truth.
GITLEAKS_VERSION="8.30.1"
DELTA_VERSION="0.19.2"

log() {
    # Single-line status prefix so source and wheel flows render consistently.
    printf '  %-12s %s\n' "$1" "$2"
}

warn_gitleaks_install_failed() {
    local reason="$1"
    echo "WARN: gitleaks install failed ($reason). Pre-commit secret-scanning will be skipped."
    echo "      Install manually from https://github.com/gitleaks/gitleaks/releases if needed."
}

warn_delta_install_failed() {
    local reason="$1"
    echo "WARN: git-delta install failed ($reason). TUI diffs will use the built-in renderer."
    echo "      Install manually from https://github.com/dandavison/delta/releases if needed."
}

# First semver in the input. Anchored to the FIRST match: a tool prints its own
# version first and may append build metadata that is itself a semver (e.g.
# `tea --version` ends with "go-sdk: v0.25.1"), which a greedy last-match would
# wrongly read as the tool version.
extract_semver() {
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d ' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d ' ' -f1
    else
        return 1
    fi
}

# ---------------------------------------------------------------------
# gitleaks -- secret scanner used by `hashd project add` and the pre-commit
# hook. Version pinned; bumps go in a dedicated PR.
# ---------------------------------------------------------------------
install_gitleaks() {
    local version="$GITLEAKS_VERSION"
    local bin="$TOOLS_DIR/gitleaks"

    local arch
    case "$RAW_ARCH" in
        x86_64|amd64)   arch=x64 ;;
        aarch64|arm64)  arch=arm64 ;;
        *)
            warn_gitleaks_install_failed "unsupported arch: $RAW_ARCH"
            return 0
            ;;
    esac

    # Idempotency: skip if the installed binary already reports the
    # pinned version. `gitleaks version` prints e.g. "v8.30.1" or
    # "8.30.1" depending on build; accept both.
    if [ -x "$bin" ]; then
        local installed
        installed="$("$bin" version 2>/dev/null | tr -d 'v' | head -1 || true)"
        if [ "$installed" = "$version" ]; then
            log "gitleaks" "$version (ok)"
            return 0
        fi
        log "gitleaks" "replacing stale $installed with $version"
        if ! rm -f "$bin"; then
            warn_gitleaks_install_failed "could not remove stale $bin"
            return 0
        fi
    fi

    local asset="gitleaks_${version}_${OS}_${arch}.tar.gz"
    local url="https://github.com/gitleaks/gitleaks/releases/download/v${version}/${asset}"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    # --retry 3 + --retry-delay covers transient GitHub release blips.
    # --connect-timeout bounds stalled DNS/TCP handshake.
    # --max-time 120 bounds the whole transfer: gitleaks is ~10 MB; at
    # 100 KB/s (a genuinely bad link) that's ~100s, so 120s gives
    # breathing room without masking a pathological hang as "slow
    # but OK." Revisit per-tool if a future tool is meaningfully
    # larger.
    if ! curl --fail --silent --location \
        --retry 3 --retry-delay 2 \
        --connect-timeout 10 --max-time 120 \
        "$url" -o "$tmp/$asset" 2>/dev/null; then
        warn_gitleaks_install_failed "download failed"
        return 0
    fi
    if ! tar -xzf "$tmp/$asset" -C "$tmp" gitleaks; then
        warn_gitleaks_install_failed "archive extraction failed"
        return 0
    fi
    if ! mv "$tmp/gitleaks" "$bin"; then
        warn_gitleaks_install_failed "could not write $bin"
        return 0
    fi
    if ! chmod +x "$bin"; then
        warn_gitleaks_install_failed "could not mark $bin executable"
        return 0
    fi
    log "gitleaks" "$version -> $bin"
}

# ---------------------------------------------------------------------
# git-delta -- optional client-side formatter for TUI diffs. It formats
# REST-fetched diff text only; it does not read repositories or mutate state.
# Version pinned; bumps go in a dedicated PR.
# ---------------------------------------------------------------------
install_delta() {
    local version="$DELTA_VERSION"
    local bin="$TOOLS_DIR/delta"

    local target
    local expected_sha
    case "$OS/$RAW_ARCH" in
        linux/x86_64|linux/amd64)
            target=x86_64-unknown-linux-gnu
            expected_sha="8e695c5f586a8c53d6c3b01be0b4a422ed218bfed2a56191caebe373a1c18ab2"
            ;;
        linux/aarch64|linux/arm64)
            target=aarch64-unknown-linux-gnu
            expected_sha="0bfce159a5cddd5feb3d6db4a616d883ff51253ce08ac7ec11cb1d208cfaab9e"
            ;;
        darwin/aarch64|darwin/arm64)
            target=aarch64-apple-darwin
            expected_sha="9be36612a5a13e9e386dc498fb8e50dc87c72ee42b63db0ea05b32f99a72a69a"
            ;;
        *)
            warn_delta_install_failed "unsupported platform: $OS/$RAW_ARCH"
            return 0
            ;;
    esac

    if [ -x "$bin" ]; then
        local installed
        installed="$("$bin" --version 2>/dev/null | extract_semver || true)"
        if [ "$installed" = "$version" ]; then
            log "git-delta" "$version (ok)"
            return 0
        fi
        log "git-delta" "replacing stale ${installed:-unknown} with $version"
        if ! rm -f "$bin"; then
            warn_delta_install_failed "could not remove stale $bin"
            return 0
        fi
    fi

    local asset="delta-${version}-${target}.tar.gz"
    local url="https://github.com/dandavison/delta/releases/download/${version}/${asset}"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    if ! curl --fail --silent --location \
        --retry 3 --retry-delay 2 \
        --connect-timeout 10 --max-time 120 \
        "$url" -o "$tmp/$asset" 2>/dev/null; then
        warn_delta_install_failed "download failed"
        return 0
    fi

    local actual_sha
    if ! actual_sha="$(sha256_file "$tmp/$asset")"; then
        warn_delta_install_failed "no SHA256 tool available"
        return 0
    fi
    if [ "$actual_sha" != "$expected_sha" ]; then
        warn_delta_install_failed "checksum mismatch for $asset"
        return 0
    fi

    if ! tar -xzf "$tmp/$asset" -C "$tmp"; then
        warn_delta_install_failed "archive extraction failed"
        return 0
    fi

    local extracted
    extracted="$(find "$tmp" -name delta -type f -perm -u+x | head -1)"
    if [ -z "$extracted" ]; then
        extracted="$(find "$tmp" -name delta -type f | head -1)"
    fi
    if [ -z "$extracted" ]; then
        warn_delta_install_failed "archive did not contain delta"
        return 0
    fi

    if ! install -m 755 "$extracted" "$bin"; then
        warn_delta_install_failed "could not write $bin"
        return 0
    fi

    local installed_after
    installed_after="$("$bin" --version 2>/dev/null | extract_semver || true)"
    if [ "$installed_after" != "$version" ]; then
        warn_delta_install_failed "version check returned '${installed_after:-unknown}', expected $version"
        return 0
    fi

    log "git-delta" "$version -> $bin"
}

# ---------------------------------------------------------------------
# Run installers. Add future install_* calls here.
# ---------------------------------------------------------------------
echo "Installing external tools into $TOOLS_DIR"
install_gitleaks
install_delta
echo "Tool install complete."
