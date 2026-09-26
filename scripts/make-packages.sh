#!/usr/bin/env bash
# Create distribution packages for OpenCode Android
#
# Usage: ./scripts/make-packages.sh
#
# Creates three package formats:
# 1. ZIP: opencode-${VERSION}-android-aarch64.zip (standalone binary)
# 2. Pacman: opencode-${VERSION}-1-aarch64.pkg.tar.xz (Termux pacman format)
# 3. Deb: opencode_${VERSION}_aarch64.deb (old Termux deb format)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

OPENCODE_BINARY="$DIST_DIR/opencode"
PKG_DIR="$WORK_DIR/packages"

if [ ! -f "$OPENCODE_BINARY" ]; then
    echo "ERROR: OpenCode binary not found at $OPENCODE_BINARY"
    echo "       Run scripts/build-opencode.sh first."
    exit 1
fi

echo "=== Creating packages for OpenCode v${OPENCODE_VERSION} ==="

# Native asset tree for the OTUI_ASSET_ROOT bypass (see launcher).
# Key layout required by @opentui/core: <root>/@opentui/core-linux-arm64/libopentui.so
ARM64_SO=""
for candidate in \
    "$OPENTUI_SRC/packages/core/src/lib/aarch64-linux-android/libopentui.so" \
    "$OPENTUI_SRC/packages/lib/aarch64-linux-android/libopentui.so"
do
    if [ -f "$candidate" ]; then
        ARM64_SO="$candidate"
        break
    fi
done
if [ -z "$ARM64_SO" ]; then
    echo "ERROR: ARM64 libopentui.so not found under $OPENTUI_SRC"
    echo "       Run scripts/build-opentui.sh first."
    exit 1
fi
echo ">>> Android libopentui.so for asset tree: $ARM64_SO"
ASSET_SIZE=$(stat -c%s "$ARM64_SO")

# Tree-sitter parser worker, shipped as a real file (see launcher).
PARSER_WORKER="$DIST_DIR/parser.worker.js"
if [ ! -f "$PARSER_WORKER" ]; then
    echo "ERROR: parser.worker.js not found at $PARSER_WORKER"
    echo "       Run scripts/build-opencode.sh first."
    exit 1
fi
WORKER_SIZE=$(stat -c%s "$PARSER_WORKER")

BINARY_SIZE=$(stat -c%s "$OPENCODE_BINARY")
BUILD_DATE=$(date +%s)

# Clean up
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"

# Termux launcher for the standalone binary.
# The binary needs a writable /tmp (module cache, workers), which stock
# Android does not provide. When /tmp is not writable, bind a private tmp
# over it via proot (Termux package, must be installed).
write_termux_launcher() {
    cat > "$1" << 'LAUNCHER_EOF'
#!/data/data/com.termux/files/usr/bin/sh
# opencode launcher for Termux.
if [ -z "${PREFIX:-}" ]; then
    echo 'opencode: $PREFIX is not set (not a Termux shell?)' >&2
    exit 1
fi
BIN="$PREFIX/libexec/opencode/opencode.bin"
if [ ! -x "$BIN" ]; then
    echo "opencode: binary not found at $BIN" >&2
    exit 1
fi
: "${TMPDIR:=$PREFIX/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true
# Native library bypass: @opentui/core resolves its .so via OTUI_ASSET_ROOT
# before attempting any import. Bare package imports do not resolve inside
# the standalone binary, so the ARM64 .so ships as a real file and is found
# here. Without this the TUI crashes with 'loadedPath.startsWith' on undefined.
export OTUI_ASSET_ROOT="$PREFIX/lib/opentui-assets"
# Tree-sitter parser worker: the standalone cannot resolve it via import, so
# point @opentui/core at the copy shipped next to the binary.
export OTUI_TREE_SITTER_WORKER_PATH="$PREFIX/libexec/opencode/parser.worker.js"
if [ -d /tmp ] && [ -w /tmp ]; then
    exec "$BIN" "$@"
fi
if ! command -v proot >/dev/null 2>&1; then
    echo "opencode: /tmp is not writable and 'proot' is not installed." >&2
    echo "opencode: run: pkg install proot" >&2
    exit 1
fi
# Some Android kernels block the seccomp acceleration proot relies on
# (ptrace(TRACEME): Operation not permitted). Fall back to pure-ptrace mode.
export PROOT_NO_SECCOMP=1
exec proot -b "$TMPDIR:/tmp" "$BIN" "$@"
LAUNCHER_EOF
}

# ==========================================
# 1. ZIP package
# ==========================================
echo ">>> Creating ZIP package..."
ZIP_NAME="opencode-${OPENCODE_VERSION}-android-aarch64.zip"
ZIP_STAGING="$PKG_DIR/zip-staging"
mkdir -p "$ZIP_STAGING"
cp "$OPENCODE_BINARY" "$ZIP_STAGING/opencode.bin"
chmod 755 "$ZIP_STAGING/opencode.bin"
cp "$PARSER_WORKER" "$ZIP_STAGING/parser.worker.js"
mkdir -p "$ZIP_STAGING/opentui-assets/@opentui/core-linux-arm64"
cp "$ARM64_SO" "$ZIP_STAGING/opentui-assets/@opentui/core-linux-arm64/libopentui.so"
write_termux_launcher "$ZIP_STAGING/opencode"
chmod 755 "$ZIP_STAGING/opencode"
WRAPPER_SIZE=$(stat -c%s "$ZIP_STAGING/opencode")
cd "$ZIP_STAGING"
zip -9 -r "$PKG_DIR/$ZIP_NAME" opencode opencode.bin parser.worker.js opentui-assets
echo "    Created $ZIP_NAME"

# ==========================================
# 2. Pacman package (Termux)
# ==========================================
echo ">>> Creating pacman package..."
PACMAN_STAGING="$PKG_DIR/pacman-staging"
mkdir -p "$PACMAN_STAGING/data/data/com.termux/files/usr/bin"
mkdir -p "$PACMAN_STAGING/data/data/com.termux/files/usr/libexec/opencode"
mkdir -p "$PACMAN_STAGING/data/data/com.termux/files/usr/lib/opentui-assets/@opentui/core-linux-arm64"

cp "$OPENCODE_BINARY" "$PACMAN_STAGING/data/data/com.termux/files/usr/libexec/opencode/opencode.bin"
chmod 755 "$PACMAN_STAGING/data/data/com.termux/files/usr/libexec/opencode/opencode.bin"
cp "$PARSER_WORKER" "$PACMAN_STAGING/data/data/com.termux/files/usr/libexec/opencode/parser.worker.js"
cp "$ARM64_SO" "$PACMAN_STAGING/data/data/com.termux/files/usr/lib/opentui-assets/@opentui/core-linux-arm64/libopentui.so"
write_termux_launcher "$PACMAN_STAGING/data/data/com.termux/files/usr/bin/opencode"
chmod 755 "$PACMAN_STAGING/data/data/com.termux/files/usr/bin/opencode"

# Create .PKGINFO
cat > "$PACMAN_STAGING/.PKGINFO" << EOF
pkgname = opencode
pkgver = ${OPENCODE_VERSION}-1
pkgdesc = AI-powered coding assistant for the terminal
url = https://github.com/anomalyco/opencode
builddate = ${BUILD_DATE}
packager = opencode-termux
size = $((BINARY_SIZE + WRAPPER_SIZE + ASSET_SIZE + WORKER_SIZE))
arch = aarch64
license = MIT
depend = ripgrep
depend = proot
EOF

PACMAN_NAME="opencode-${OPENCODE_VERSION}-1-aarch64.pkg.tar.xz"
cd "$PACMAN_STAGING"
tar cf - .PKGINFO data | xz -9 > "$PKG_DIR/$PACMAN_NAME"
echo "    Created $PACMAN_NAME"

# ==========================================
# 3. Deb package (old Termux format)
# ==========================================
echo ">>> Creating deb package..."
DEB_STAGING="$PKG_DIR/deb-staging"
mkdir -p "$DEB_STAGING/data/data/data/com.termux/files/usr/bin"
mkdir -p "$DEB_STAGING/data/data/data/com.termux/files/usr/libexec/opencode"
mkdir -p "$DEB_STAGING/data/data/data/com.termux/files/usr/lib/opentui-assets/@opentui/core-linux-arm64"
mkdir -p "$DEB_STAGING/DEBIAN"

cp "$OPENCODE_BINARY" "$DEB_STAGING/data/data/data/com.termux/files/usr/libexec/opencode/opencode.bin"
chmod 755 "$DEB_STAGING/data/data/data/com.termux/files/usr/libexec/opencode/opencode.bin"
cp "$PARSER_WORKER" "$DEB_STAGING/data/data/data/com.termux/files/usr/libexec/opencode/parser.worker.js"
cp "$ARM64_SO" "$DEB_STAGING/data/data/data/com.termux/files/usr/lib/opentui-assets/@opentui/core-linux-arm64/libopentui.so"
write_termux_launcher "$DEB_STAGING/data/data/data/com.termux/files/usr/bin/opencode"
chmod 755 "$DEB_STAGING/data/data/data/com.termux/files/usr/bin/opencode"

# Create control file
INSTALLED_SIZE=$(((BINARY_SIZE + WRAPPER_SIZE + ASSET_SIZE + WORKER_SIZE) / 1024))
cat > "$DEB_STAGING/DEBIAN/control" << EOF
Package: opencode
Version: ${OPENCODE_VERSION}
Architecture: aarch64
Maintainer: Guy Sheffer <guysoft@gmail.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: ripgrep, proot
Section: utils
Priority: optional
Homepage: https://github.com/anomalyco/opencode
Description: AI-powered coding assistant for the terminal
 OpenCode is an AI-powered coding assistant that runs in the terminal.
 This package provides a standalone binary compiled for Android/Termux.
EOF

DEB_NAME="opencode_${OPENCODE_VERSION}_aarch64.deb"

# Build deb manually (dpkg-deb may not be available)
cd "$DEB_STAGING/data"
tar czf "$DEB_STAGING/data.tar.gz" data
cd "$DEB_STAGING/DEBIAN"
tar czf "$DEB_STAGING/control.tar.gz" control
echo "2.0" > "$DEB_STAGING/debian-binary"
cd "$DEB_STAGING"
ar rc "$PKG_DIR/$DEB_NAME" debian-binary control.tar.gz data.tar.gz
echo "    Created $DEB_NAME"

# ==========================================
# Summary
# ==========================================
echo ""
echo "=== Packages created ==="
echo ""
ls -lh "$PKG_DIR"/*.{zip,xz,deb} 2>/dev/null
echo ""
echo "ZIP layout: opencode (launcher) + opencode.bin + parser.worker.js + opentui-assets/."
echo "Install on Termux (requires: ripgrep, proot):"
echo "  pacman -U $PACMAN_NAME"
echo "  dpkg -i $DEB_NAME"
echo "  unzip $ZIP_NAME && mkdir -p \$PREFIX/libexec/opencode && mv opencode \$PREFIX/bin/ && mv opencode.bin parser.worker.js \$PREFIX/libexec/opencode/ && mv opentui-assets \$PREFIX/lib/"
