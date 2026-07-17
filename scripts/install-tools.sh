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
# Temporal is the execution engine's sidecar. Version pinned; bumps go
# in a dedicated PR alongside the Go-side pin (server/internal/temporal).
TEMPORAL_VERSION="1.31.2"
# Forge CLIs. hashd invokes these by absolute path out of TOOLS_DIR and never
# from PATH, so a user's own gh/tea can neither shadow nor break it. A project
# only needs its own forge's CLI; the rest are inert.
GH_VERSION="2.93.0"
GLAB_VERSION="1.101.0"
BKT_VERSION="0.28.1"
TEA_VERSION="0.14.1"

log() {
    # Single-line status prefix so source and wheel flows render consistently.
    printf '  %-12s %s\n' "$1" "$2"
}

warn_gitleaks_install_failed() {
    local reason="$1"
    echo "WARN: gitleaks install failed ($reason). Pre-commit secret-scanning will be skipped."
    echo "      Fix: re-run this script, or place a gitleaks binary at $TOOLS_DIR/gitleaks"
    echo "      (hashd only runs the copy in its tools dir; a system install is not used)."
}

warn_temporal_install_failed() {
    local reason="$1"
    echo "WARN: temporal install failed ($reason). hashd runs its workflows on the"
    echo "      temporal sidecar, so it will not start until this succeeds."
    echo "      Fix: re-run this script, or place temporal-server/temporal-sql-tool"
    echo "      in $TOOLS_DIR (hashd only runs the copies in its tools dir)."
}

warn_delta_install_failed() {
    local reason="$1"
    echo "WARN: git-delta install failed ($reason). TUI diffs will use the built-in renderer."
    echo "      Fix: re-run this script, or place a delta binary at $TOOLS_DIR/delta"
    echo "      (hashd only runs the copy in its tools dir; a system install is not used)."
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

# harden_darwin_binary: on macOS a freshly-downloaded binary pays a one-time
# Gatekeeper/notarization cost on first exec (and, if unsigned, may be refused
# outright). Strip the quarantine bit and ad-hoc re-sign so the first run is
# cheap and never blocked. Mirrors install_cbm below. codesign/xattr are
# macOS base tools; tolerate failures rather than fail the install over a
# hardening nicety.
harden_darwin_binary() {
    [ "$OS" = darwin ] || return 0
    local bin="$1"
    xattr -d com.apple.quarantine "$bin" 2>/dev/null || true
    codesign --remove-signature "$bin" 2>/dev/null || true
    codesign --sign - --force "$bin" 2>/dev/null || true
}

# warm_tool: run a tool once so its expensive first-launch cost (macOS Gatekeeper
# assessment / dyld closure build) is paid here at install time, not later on a
# latency-budgeted probe like `hashd doctor` -- which would SIGKILL a cold exec
# mid-assessment and then re-time-out on every run. Output and exit code are
# discarded; this is a warm-up, not a gate.
warm_tool() {
    "$@" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------
# gitleaks -- secret scanner used by `hashd project add` and the pre-commit
# hook. Version pinned; bumps go in a dedicated PR.
# ---------------------------------------------------------------------
install_temporal() {
    local version="$TEMPORAL_VERSION"
    local server_bin="$TOOLS_DIR/temporal-server"
    local sql_bin="$TOOLS_DIR/temporal-sql-tool"

    local target
    local expected_sha
    case "$OS/$RAW_ARCH" in
        linux/x86_64|linux/amd64)
            target=linux_amd64
            expected_sha="36d3227fbbc522409bd2ac259db58d23f190e83f55f1aebe85564190b34fae16"
            ;;
        linux/aarch64|linux/arm64)
            target=linux_arm64
            expected_sha="662a79276ce97fac71637a76727278b28849078caa4dda25f3b7ba0567109e8b"
            ;;
        darwin/x86_64|darwin/amd64)
            target=darwin_amd64
            expected_sha="502d711c882c5b906f948ea3c0607be9def95119c6a2130883b9c9c757dbc4cb"
            ;;
        darwin/aarch64|darwin/arm64)
            target=darwin_arm64
            expected_sha="cef6f8a28da8fe276b1b502062f05a0cff9466451d4f07f70ec1c5a0cbd3d4fb"
            ;;
        *)
            warn_temporal_install_failed "unsupported platform: $OS/$RAW_ARCH"
            return 0
            ;;
    esac

    if [ -x "$server_bin" ] && [ -x "$sql_bin" ]; then
        local installed
        installed="$("$server_bin" --version 2>/dev/null | extract_semver || true)"
        if [ "$installed" = "$version" ]; then
            log "temporal" "$version (ok)"
            return 0
        fi
        log "temporal" "replacing stale ${installed:-unknown} with $version"
        if ! rm -f "$server_bin" "$sql_bin"; then
            warn_temporal_install_failed "could not remove stale binaries"
            return 0
        fi
    fi

    local asset="temporal_${version}_${target}.tar.gz"
    local url="https://github.com/temporalio/temporal/releases/download/v${version}/${asset}"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    if ! curl --fail --silent --location \
        --retry 3 --retry-delay 2 \
        --connect-timeout 10 --max-time 300 \
        "$url" -o "$tmp/$asset" 2>/dev/null; then
        warn_temporal_install_failed "download failed"
        return 0
    fi

    local actual_sha
    if ! actual_sha="$(sha256_file "$tmp/$asset")"; then
        warn_temporal_install_failed "no SHA256 tool available"
        return 0
    fi
    if [ "$actual_sha" != "$expected_sha" ]; then
        warn_temporal_install_failed "checksum mismatch for $asset"
        return 0
    fi

    if ! tar -xzf "$tmp/$asset" -C "$tmp"; then
        warn_temporal_install_failed "archive extraction failed"
        return 0
    fi

    mkdir -p "$TOOLS_DIR"
    local name
    for name in temporal-server temporal-sql-tool; do
        local extracted
        extracted="$(find "$tmp" -name "$name" -type f | head -1)"
        if [ -z "$extracted" ]; then
            warn_temporal_install_failed "$name missing from $asset"
            return 0
        fi
        if ! install -m 755 "$extracted" "$TOOLS_DIR/$name"; then
            warn_temporal_install_failed "could not install $name"
            return 0
        fi
        harden_darwin_binary "$TOOLS_DIR/$name"
    done
    log "temporal" "$version -> $server_bin"
}

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
    # Unlike delta below, gitleaks has no post-install version check, so without
    # this its first-ever exec would be hashd doctor's -- cold, and killed by the
    # per-probe timeout. Harden + warm here so doctor only ever sees a warm binary.
    harden_darwin_binary "$bin"
    warm_tool "$bin" version
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

    # Harden before the version check below, which doubles as the warm-up run.
    harden_darwin_binary "$bin"

    local installed_after
    installed_after="$("$bin" --version 2>/dev/null | extract_semver || true)"
    if [ "$installed_after" != "$version" ]; then
        warn_delta_install_failed "version check returned '${installed_after:-unknown}', expected $version"
        return 0
    fi

    log "git-delta" "$version -> $bin"
}


# ---------------------------------------------------------------------
# codebase-memory-mcp (cbm) -- our own pinned artifact, from
# vendor/cbm.lock. Unlike the third-party tools above it installs
# per-checkout (.cache/cbm/<platform>/), because the pin moves with the
# code: two checkouts on different branches may need different cbm
# versions, so a machine-global copy would break branch switching.
# Wheel users never take this leg -- the release wheel ships cbm inside
# the package (dist/build_wheel.sh embeds it via the cbm subcommand).
# When this script is fetched standalone (dist/install.sh pipes it over
# HTTPS), there is no repo and no lock file: the leg is skipped.
# ---------------------------------------------------------------------

cbm_die() {
    echo "ERROR: $*" >&2
    exit 1
}

cbm_verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual

    if command -v sha256sum >/dev/null 2>&1; then
        echo "${expected}  ${file}" | sha256sum -c -
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
        [[ "$actual" == "$expected" ]] || cbm_die "SHA-256 mismatch for $file: expected $expected, got $actual"
        return
    fi

    cbm_die "sha256sum or shasum is required"
}

cbm_detect_host_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

    case "$os" in
        linux*) os="linux" ;;
        darwin*) os="darwin" ;;
        msys*|mingw*|cygwin*) os="windows" ;;
        *) return 1 ;;
    esac

    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) return 1 ;;
    esac

    printf '%s-%s\n' "$os" "$arch"
}

# install_cbm [--platform P] [--dest PATH] [--verify-attestation]
install_cbm() {
    local platform=""
    local dest=""
    local verify_attestation=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --platform)
                [[ -n "${2:-}" ]] || cbm_die "missing value for --platform"
                platform="$2"
                shift 2
                ;;
            --dest)
                [[ -n "${2:-}" ]] || cbm_die "missing value for --dest"
                dest="$2"
                shift 2
                ;;
            --verify-attestation)
                verify_attestation=1
                shift
                ;;
            *)
                cbm_die "unknown cbm argument: $1"
                ;;
        esac
    done

    local script_dir repo_root lock_path
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd "$script_dir/.." && pwd)"
    lock_path="$repo_root/vendor/cbm.lock"
    [[ -f "$lock_path" ]] || cbm_die "missing $lock_path"

    if [[ -z "$platform" ]]; then
        platform="$(cbm_detect_host_platform)" || cbm_die "unsupported host for cbm platform resolution: $(uname -s)/$(uname -m)"
    fi
    if [[ -z "$dest" ]]; then
        local suffix=""
        if [[ "$platform" == windows-* ]]; then
            suffix=".exe"
        fi
        dest="$repo_root/.cache/cbm/$platform/codebase-memory-mcp$suffix"
    fi

    local metadata version url sha256 archive_name
    metadata="$(
        python3 - "$lock_path" "$platform" <<'PY'
import json
import sys
from pathlib import Path

lock = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
platform = sys.argv[2]
try:
    entry = lock["platforms"][platform]
except KeyError:
    known = ", ".join(sorted(lock.get("platforms", {})))
    raise SystemExit(f"unknown platform {platform!r}; known: {known}")

print(lock["version"])
print(entry["url"])
print(entry["sha256"])
PY
    )"
    version="$(sed -n '1p' <<< "$metadata")"
    url="$(sed -n '2p' <<< "$metadata")"
    sha256="$(sed -n '3p' <<< "$metadata")"
    archive_name="$(basename "$url")"

    # Already at the pinned version -- nothing to do. gitleaks/delta/temporal
    # all no-op like this; without it every caller re-downloads the archive,
    # and each fetch is another chance to hard-exit on a blip or burn GitHub
    # rate limit.
    #
    # NOT taken under --verify-attestation: that flag's whole job is to prove
    # the artifact's provenance, and the proof lives in the archive we would be
    # skipping. A version string self-reported by the binary on disk is not
    # evidence of anything -- the release pipeline (dist/build_wheel.sh) passes
    # this flag, so a warm cache must never be able to stand in for a real
    # `gh attestation verify`.
    if [[ "$verify_attestation" -eq 0 ]] &&
        [[ -x "$dest" ]] &&
        [[ "$("$dest" --version 2>/dev/null | awk '{print $2}')" == "${version#v}" ]]; then
        echo "cbm ${version#v} already installed at $dest"
        return 0
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/hashd-cbm-fetch.XXXXXX)"
    # EXIT, not RETURN: cbm_die exits and a set -e abort (a failed curl,
    # a checksum mismatch) never returns, so a RETURN trap would leak
    # the temp dir on exactly the failure paths. The script exits right
    # after install_cbm in every call path, so cleaning at exit is
    # equivalent for the success case.
    # Expand tmp_dir now, not at trap time:
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" EXIT

    local archive="$tmp_dir/$archive_name"
    echo "Fetching cbm $version for $platform"
    curl -fL --retry 3 --retry-delay 2 -o "$archive" "$url"

    cbm_verify_sha256 "$archive" "$sha256"

    if [[ "$verify_attestation" -eq 1 ]]; then
        command -v gh >/dev/null 2>&1 || cbm_die "gh is required for --verify-attestation"
        gh attestation verify "$archive" --repo DeusData/codebase-memory-mcp >/dev/null
    fi

    local extract_dir="$tmp_dir/extract"
    mkdir -p "$extract_dir"
    local binary
    case "$archive_name" in
        *.tar.gz)
            tar -xzf "$archive" -C "$extract_dir"
            binary="$extract_dir/codebase-memory-mcp"
            ;;
        *.zip)
            unzip -q "$archive" -d "$extract_dir"
            binary="$extract_dir/codebase-memory-mcp.exe"
            ;;
        *)
            cbm_die "unsupported cbm archive type: $archive_name"
            ;;
    esac

    [[ -f "$binary" ]] || cbm_die "archive did not contain expected cbm binary"
    mkdir -p "$(dirname "$dest")"
    # Write to a FRESH inode. macOS caches a Mach-O's code signature by vnode and
    # does not flush it when the file is rewritten in place (cp truncates in place,
    # reusing the inode). On a re-install over a previously-run binary that stale
    # cache can keep an old/invalid signature, so even a correct re-sign below would
    # silently not take effect. rm first so cp creates a new inode the kernel has
    # not cached.
    rm -f "$dest"
    cp "$binary" "$dest"
    chmod 755 "$dest"

    # macOS (especially Apple Silicon) SIGKILLs any binary whose code signature is
    # invalid or merely linker-signed, and cbm ships such darwin binaries (its own
    # installer ad-hoc force-signs them; we bypass that installer, so we must too).
    # Integrity is already verified by the sha256 check above. A plain re-sign is
    # skipped/blocked by the existing linker signature, so remove it then force an
    # ad-hoc sign. Signing happens before the first execution below, so the kernel
    # never caches a bad signature for this inode. codesign/xattr are macOS base
    # tools; failures are tolerated so a stripped-down host degrades to prior
    # behavior, not aborts.
    if [[ "$platform" == darwin-* ]]; then
        xattr -d com.apple.quarantine "$dest" 2>/dev/null || true
        codesign --remove-signature "$dest" 2>/dev/null || true
        codesign --sign - --force "$dest" 2>/dev/null || true
    fi

    local host_platform
    host_platform="$(cbm_detect_host_platform || true)"
    if [[ -n "$host_platform" && "$platform" == "$host_platform" && "$platform" != windows-* ]]; then
        local actual expected
        actual="$("$dest" --version | awk '{print $2}')"
        expected="${version#v}"
        [[ "$actual" == "$expected" ]] || cbm_die "cbm version mismatch: expected $expected, got $actual"
    fi

    log "cbm" "$version -> $dest"
}

# install_cbm_if_source_checkout: the default-run leg. Only a source
# checkout has vendor/cbm.lock; wheel users get cbm from the package.
# ---------------------------------------------------------------------
# Forge CLIs (gh / glab / bkt / tea)
#
# Vendored into TOOLS_DIR alongside gitleaks/delta. hashd runs only its own
# copies, by absolute path, so a system install is never consulted or
# substituted.
#
# Fetch failures (404, rate limit, no network) are LOUD BUT SOFT, like every
# other leg: a project only needs its own forge's CLI, so a gh outage must not
# sink an otherwise good install. This matters more than it looks -- setup.sh
# aborts the source install when this script exits non-zero, so an `exit` on a
# rate-limited download would take the whole install down with it.
#
# A checksum failure is the exception and fails closed -- see
# verify_forge_checksum. Soft is for "could not get it", not for "got something
# that is not what upstream published".
# ---------------------------------------------------------------------

forge_display_name() {
    case "$1" in
        gh) echo "GitHub" ;;
        glab) echo "GitLab" ;;
        bkt) echo "Bitbucket" ;;
        tea) echo "Gitea" ;;
        *) echo "$1" ;;
    esac
}

forge_pinned_version() {
    case "$1" in
        gh) echo "$GH_VERSION" ;;
        glab) echo "$GLAB_VERSION" ;;
        bkt) echo "$BKT_VERSION" ;;
        tea) echo "$TEA_VERSION" ;;
        *) return 1 ;;
    esac
}

forge_binary_version() {
    "$1" --version 2>/dev/null | extract_semver || true
}

# forge_asset_name <name> <version> <os:linux|darwin> <raw arch>
forge_asset_name() {
    local name="$1" version="$2" os="$3" machine="$4" arch

    case "$name" in
        gh)
            case "$machine" in
                x86_64|amd64) arch="amd64" ;;
                aarch64|arm64) arch="arm64" ;;
                *) return 1 ;;
            esac
            if [ "$os" = "darwin" ]; then
                echo "gh_${version}_macOS_${arch}.zip"
            else
                echo "gh_${version}_linux_${arch}.tar.gz"
            fi
            ;;
        glab)
            case "$machine" in
                x86_64|amd64) arch="amd64" ;;
                aarch64|arm64) arch="arm64" ;;
                *) return 1 ;;
            esac
            echo "glab_${version}_${os}_${arch}.tar.gz"
            ;;
        bkt)
            case "$machine" in
                x86_64|amd64) arch="x86_64" ;;
                aarch64|arm64) arch="arm64" ;;
                *) return 1 ;;
            esac
            echo "bkt_${version}_${os}_${arch}.tar.gz"
            ;;
        tea)
            case "$machine" in
                x86_64|amd64) arch="amd64" ;;
                aarch64|arm64) arch="arm64" ;;
                *) return 1 ;;
            esac
            echo "tea-${version}-${os}-${arch}"
            ;;
        *) return 1 ;;
    esac
}

forge_download_base_url() {
    case "$1" in
        gh) echo "https://github.com/cli/cli/releases/download/v${2}" ;;
        glab) echo "https://gitlab.com/gitlab-org/cli/-/releases/v${2}/downloads" ;;
        bkt) echo "https://github.com/avivsinai/bitbucket-cli/releases/download/v${2}" ;;
        tea) echo "https://dl.gitea.com/tea/${2}" ;;
        *) return 1 ;;
    esac
}

forge_checksums_name() {
    case "$1" in
        gh) echo "gh_${2}_checksums.txt" ;;
        glab|bkt|tea) echo "checksums.txt" ;;
        *) return 1 ;;
    esac
}

# verify_forge_checksum <asset path> <checksums path>
#
# FAILS CLOSED, deliberately: a mismatch or a missing entry aborts the whole
# run rather than warning. Unlike a 404 or a rate-limit -- which are soft, and
# handled by the curl callers -- a hash that does not match the publisher's is
# a supply-chain signal, and the right response to "this binary is not what
# upstream says it is" is to stop, not to carry on without it.
verify_forge_checksum() {
    local asset="$1" checksums="$2"
    local asset_name expected actual line_sum line_file

    asset_name="$(basename "$asset")"
    # Look the hash up without awk (minimal images may lack it). The file is
    # `<sha>  <filename>` per line; match the filename exactly.
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

    if ! actual="$(sha256_file "$asset")"; then
        echo "ERROR: sha256sum or shasum is required to verify downloaded forge CLI archives."
        exit 1
    fi
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: SHA256 mismatch for $asset_name"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        exit 1
    fi
}

warn_forge_install_failed() {
    local name="$1" display="$2" reason="$3"
    echo "WARN: ${display} CLI (${name}) install failed (${reason})."
    echo "      ${display} features will not work until this is fixed; other forges are unaffected."
    echo "      Fix: re-run this script, or place a ${name} binary in ${TOOLS_DIR}"
    echo "      (hashd only runs the copies in its tools dir)."
}

# install_forge_cli <name> -- vendors the pinned CLI. Returns non-zero on
# failure; the caller warns and continues.
install_forge_cli() {
    local name="$1"
    local version display asset_name base_url checksums_name tmp extract_dir found installed staged

    version="$(forge_pinned_version "$name")" || return 1
    display="$(forge_display_name "$name")"

    # Skip only when OUR copy already matches the pin. The system PATH is
    # deliberately not consulted -- hashd runs the bundled path regardless.
    if [ -x "$TOOLS_DIR/$name" ] && [ "$(forge_binary_version "$TOOLS_DIR/$name")" = "$version" ]; then
        log "$name" "$version already installed"
        return 0
    fi

    asset_name="$(forge_asset_name "$name" "$version" "$OS" "$RAW_ARCH")" || {
        echo "  unsupported platform for $name: $OS/$RAW_ARCH" >&2
        return 1
    }
    base_url="$(forge_download_base_url "$name" "$version")" || return 1
    checksums_name="$(forge_checksums_name "$name" "$version")" || return 1

    tmp="$(mktemp -d)" || return 1
    extract_dir="$tmp/extract"
    mkdir -p "$extract_dir"
    # RETURN covers the soft paths; EXIT covers verify_forge_checksum's hard
    # exit, which would otherwise strand the *unverified* download on disk. The
    # EXIT trap is global and each call overwrites the last, which is harmless:
    # by then the previous call's RETURN trap has already removed its dir.
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN EXIT

    # Bounded like every other download here: --retry alone still hangs forever
    # on a black-holed connect or a stalled transfer, and this runs inside
    # setup.sh.
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 300 \
        -o "$tmp/$asset_name" "$base_url/$asset_name" || return 1
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
        -o "$tmp/$checksums_name" "$base_url/$checksums_name" || return 1
    # No `if !` here: this fails closed and exits, it does not return.
    verify_forge_checksum "$tmp/$asset_name" "$tmp/$checksums_name"

    case "$asset_name" in
        *.tar.gz)
            tar -xzf "$tmp/$asset_name" -C "$extract_dir" || return 1
            ;;
        *.zip)
            if ! command -v unzip >/dev/null 2>&1; then
                echo "  unzip is required to extract $asset_name" >&2
                return 1
            fi
            unzip -q "$tmp/$asset_name" -d "$extract_dir" || return 1
            ;;
        tea-*)
            # tea ships a bare binary, not an archive.
            install -m 755 "$tmp/$asset_name" "$extract_dir/$name" || return 1
            ;;
        *)
            echo "  unsupported archive type: $asset_name" >&2
            return 1
            ;;
    esac

    found="$(find "$extract_dir" -name "$name" -type f -perm -u+x | head -1)"
    [ -n "$found" ] || found="$(find "$extract_dir" -name "$name" -type f | head -1)"
    if [ -z "$found" ]; then
        echo "  could not find $name inside $asset_name" >&2
        return 1
    fi

    # Stage, validate, then rename into place. Installing first and checking
    # after would leave a binary that failed its own version check sitting in
    # the tools dir -- and hashd runs only what is in the tools dir. Staging
    # inside TOOLS_DIR (not $tmp) keeps the rename on one filesystem, so it is
    # atomic: a concurrent reader sees the old binary or the new one, never a
    # half-written file, and an existing good copy survives a failed upgrade.
    mkdir -p "$TOOLS_DIR"
    staged="$TOOLS_DIR/.$name.new"
    install -m 755 "$found" "$staged" || return 1

    installed="$(forge_binary_version "$staged")"
    if [ "$installed" != "$version" ]; then
        rm -f "$staged"
        echo "  downloaded $name reports '${installed:-unknown}', expected $version -- not installed" >&2
        return 1
    fi
    mv -f "$staged" "$TOOLS_DIR/$name" || { rm -f "$staged"; return 1; }
    log "$name" "$version -> $TOOLS_DIR/$name"
}

# install_forge_clis installs all four, each independently soft.
install_forge_clis() {
    local name display failures=""
    for name in gh glab bkt tea; do
        display="$(forge_display_name "$name")"
        if ! install_forge_cli "$name"; then
            warn_forge_install_failed "$name" "$display" "see the output above"
            failures="$failures $name"
        fi
    done
    if [ -n "$failures" ]; then
        echo "NOTE: forge CLIs that failed to install:${failures}. \`hashd doctor\` tracks this."
    fi
    return 0
}

install_cbm_if_source_checkout() {
    local script_dir lock_path
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 0
    lock_path="$script_dir/../vendor/cbm.lock"
    [[ -f "$lock_path" ]] || return 0
    install_cbm
}

# ---------------------------------------------------------------------
# --- Entry point ---
#
# Everything above this marker is definitions only, so the install tests can
# source it without running an install. Keep the marker line intact.
#
# `install-tools.sh cbm [flags]` installs only cbm with
# explicit platform/dest control (setup.sh and dist/build_wheel.sh use
# this); `install-tools.sh temporal` vendors only the temporal sidecar
# (the CI candidate-smoke gate uses this to leave its tool env otherwise
# unchanged); a bare run installs everything, taking the cbm leg only on
# a source checkout. Add future install_* calls here.
# ---------------------------------------------------------------------
if [[ "${1:-}" == "cbm" ]]; then
    shift
    install_cbm "$@"
    exit 0
fi
if [[ "${1:-}" == "temporal" ]]; then
    install_temporal
    exit 0
fi
if [[ -n "${1:-}" ]]; then
    echo "install-tools: unknown subcommand: $1 (expected 'cbm', 'temporal', or no argument)" >&2
    exit 2
fi

echo "Installing external tools into $TOOLS_DIR"
install_gitleaks
install_delta
install_temporal
install_forge_clis
install_cbm_if_source_checkout
echo "Tool install complete."
