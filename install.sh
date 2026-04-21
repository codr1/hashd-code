#!/bin/bash
# hashd installer
# Usage: curl -fsSL https://raw.githubusercontent.com/codr1/hashd-code/main/install.sh | bash
set -e

REPO="codr1/hashd-code"

extract_first_major_minor() {
    sed -nE 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/p' | head -1
}

extract_json_string_field() {
    local field="$1"
    sed -nE "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\\1/p" | head -1
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
        echo ""
        echo "ERROR: Could not install pipx (pip is not available)."
        echo ""
        echo "  Install pipx for your platform, then re-run this script:"
        echo "    Debian/Ubuntu: sudo apt update && sudo apt install pipx"
        echo "    Arch:          sudo pacman -S python-pipx"
        echo "    macOS:         brew install pipx"
        exit 1
    fi
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

echo "  Looking for: $WHEEL_PATTERN"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Download matching wheel
if command -v gh &>/dev/null; then
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
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
fi

WHEEL=$(find "$WORK_DIR" -name '*.whl' | head -1)
if [ -z "$WHEEL" ]; then
    echo ""
    echo "ERROR: No wheel found for $PLATFORM/$MACHINE"
    echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    exit 1
fi

echo "  Downloaded: $(basename "$WHEEL")"

# --- Install ---
echo ""
echo "Installing hashd..."
pipx install --force "$WHEEL" 2>&1 | grep -v "^$" | grep -v '[✨🌟⚠️]'

# Ensure ~/.local/bin is on PATH
pipx ensurepath 2>/dev/null || true

# --- Install gitleaks (secrets scanner) ---
GITLEAKS_VERSION="8.30.1"
GITLEAKS_REPO="gitleaks/gitleaks"
HASHD_TOOLS="$HOME/.hashd/tools/bin"

# Map platform/arch to gitleaks asset naming
case "$PLATFORM" in
    linux)  GL_OS="linux" ;;
    macosx) GL_OS="darwin" ;;
esac
case "$MACHINE" in
    x86_64)  GL_ARCH="x64" ;;
    aarch64) GL_ARCH="arm64" ;;
esac

GL_ASSET="gitleaks_${GITLEAKS_VERSION}_${GL_OS}_${GL_ARCH}.tar.gz"
GL_INSTALLED="$HASHD_TOOLS/gitleaks"

if [ -x "$GL_INSTALLED" ]; then
    echo ""
    echo "  gitleaks:  already installed at $GL_INSTALLED"
else
    echo ""
    echo "Installing gitleaks $GITLEAKS_VERSION..."
    mkdir -p "$HASHD_TOOLS"

    GL_URL="https://github.com/$GITLEAKS_REPO/releases/download/v${GITLEAKS_VERSION}/${GL_ASSET}"
    curl -fsSL "$GL_URL" -o "$WORK_DIR/$GL_ASSET"
    tar -xzf "$WORK_DIR/$GL_ASSET" -C "$WORK_DIR" gitleaks
    mv "$WORK_DIR/gitleaks" "$GL_INSTALLED"
    chmod +x "$GL_INSTALLED"
    echo "  gitleaks:  $GITLEAKS_VERSION -> $GL_INSTALLED"
fi

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
