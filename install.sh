#!/usr/bin/env bash
# hashd installer
# Usage: curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | sh
set -euo pipefail

REPO="codr1/hashd-code"

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
for cmd in python3.14 python3.13 python3.12 python3.11 python3; do
    if command -v "$cmd" &>/dev/null; then
        version=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)
        if [ "$major" -ge 3 ] && [ "$minor" -ge 11 ]; then
            PYTHON="$cmd"
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
    echo "    macOS:         brew install python@3.13"
    echo "    Or:            https://www.python.org/downloads/"
    exit 1
fi

# --- Check/install pipx ---
if ! command -v pipx &>/dev/null; then
    echo ""
    echo "Installing pipx..."
    "$PYTHON" -m pip install --user pipx 2>/dev/null || {
        echo ""
        echo "ERROR: Could not install pipx."
        echo ""
        echo "  Install manually:"
        echo "    Arch:          sudo pacman -S python-pipx"
        echo "    Debian/Ubuntu: sudo apt install pipx"
        echo "    macOS:         brew install pipx"
        echo "    Or:            $PYTHON -m pip install --user pipx"
        exit 1
    }
    "$PYTHON" -m pipx ensurepath 2>/dev/null || true
fi

echo "  pipx:     $(pipx --version 2>/dev/null || echo 'installed')"

# --- Find latest release ---
echo ""
echo "Finding latest release..."

# Try gh CLI first, fall back to curl
if command -v gh &>/dev/null; then
    RELEASE_TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || echo "")
else
    RELEASE_TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | grep -oP '(?<=": ")[^"]+' || echo "")
fi

if [ -z "$RELEASE_TAG" ]; then
    echo "ERROR: No releases found at github.com/$REPO"
    echo "  Check https://github.com/$REPO/releases"
    exit 1
fi

echo "  Latest:   $RELEASE_TAG"

# --- Find matching wheel ---
# Wheel naming: hashd-{version}-cp{pyver}-cp{pyver}-{platform}_{machine}.whl
PY_TAG="cp$(echo "$version" | tr -d '.')"
WHEEL_PATTERN="hashd-*-${PY_TAG}-${PY_TAG}-*${MACHINE}*.whl"

echo "  Looking for: $WHEEL_PATTERN"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Download matching wheel
if command -v gh &>/dev/null; then
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$WHEEL_PATTERN" --dir "$TMPDIR" 2>/dev/null
else
    # Fall back to curl from release assets
    ASSETS_URL="https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG"
    WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
        | grep '"browser_download_url"' \
        | grep "$MACHINE" \
        | grep "$PY_TAG" \
        | head -1 \
        | grep -oP '(?<=": ")[^"]+')

    if [ -z "$WHEEL_URL" ]; then
        echo ""
        echo "ERROR: No wheel found for Python $version on $PLATFORM/$MACHINE"
        echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
        exit 1
    fi

    curl -fsSL -o "$TMPDIR/$(basename "$WHEEL_URL")" "$WHEEL_URL"
fi

WHEEL=$(ls "$TMPDIR"/*.whl 2>/dev/null | head -1)
if [ -z "$WHEEL" ]; then
    echo ""
    echo "ERROR: No matching wheel found for Python $version on $PLATFORM/$MACHINE"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi

echo "  Downloaded: $(basename "$WHEEL")"

# --- Install ---
echo ""
echo "Installing hashd..."
pipx install --force "$WHEEL" 2>&1 | grep -v "^$"

echo ""
echo "Done! Run 'wf --help' to get started."
echo ""
echo "Next steps:"
echo "  wf project add /path/to/your/repo"
echo ""
