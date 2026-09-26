#!/usr/bin/env bash
# Create distribution packages for OpenCode Android
#
# Usage: ./scripts/make-packages.sh
#
# Creates three package formats:
# 1. ZIP: opencode-${VERSION}-android-aarch64.zip (standalone, flat)
# 2. Pacman: opencode-${VERSION}-1-aarch64.pkg.tar.xz (Termux pacman format)
# 3. Deb: opencode_${VERSION}_aarch64.deb (old Termux deb format)
#
# Package layout:
#   bin/opencode                                          wrapper (LD_PRELOAD, env)
#   libexec/opencode/opencode.bin                         real binary
#   libexec/opencode/parser.worker.js                     tree-sitter worker
#   lib/libtagfix.so                                      disable bionic heap tagging
#   lib/libc++_shared.so                                  NDK C++ runtime for Bun JIT
#   lib/opentui-assets/@opentui/core-linux-*/libopentui.so  native renderer
#   lib/librust_pty_arm64.so                              optional Android pty lib
#
# Runtime fixes ported from guysoft/opencode-termux feature/opencode-latest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

OPENCODE_BINARY="$DIST_DIR/opencode"
PKG_DIR="$WORK_DIR/packages"
WRAPPER_SCRIPT="$REPO_ROOT/bin/opencode"
TAGFIX_SRC="$REPO_ROOT/src/libtagfix.c"

if [ ! -f "$OPENCODE_BINARY" ]; then
    echo "ERROR: OpenCode binary not found at $OPENCODE_BINARY"
    echo "       Run scripts/build-opencode.sh first."
    exit 1
fi
if [ ! -f "$WRAPPER_SCRIPT" ]; then
    echo "ERROR: wrapper not found at $WRAPPER_SCRIPT"
    exit 1
fi
if [ ! -f "$TAGFIX_SRC" ]; then
    echo "ERROR: $TAGFIX_SRC not found"
    exit 1
fi

echo "=== Creating packages for OpenCode v${OPENCODE_VERSION} ==="

# Android libopentui.so (both opentui layouts).
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
echo ">>> Using libopentui.so: $ARM64_SO"

# Tree-sitter parser worker (shipped as a real file).
PARSER_WORKER="$DIST_DIR/parser.worker.js"
if [ ! -f "$PARSER_WORKER" ]; then
    echo "ERROR: parser.worker.js not found at $PARSER_WORKER"
    echo "       Run scripts/build-opencode.sh first."
    exit 1
fi

BINARY_SIZE=$(stat -c%s "$OPENCODE_BINARY")
BUILD_DATE=$(date +%s)

# Clean up
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"
cd "$PKG_DIR"

# ==========================================
# Native support libraries
# ==========================================
echo ">>> Compiling libtagfix.so..."
"$ANDROID_CC" -shared -fPIC -O2 -o "$PKG_DIR/libtagfix.so" "$TAGFIX_SRC"
echo "    $(stat -c%s "$PKG_DIR/libtagfix.so") bytes"

echo ">>> Copying libc++_shared.so..."
LIBCPP_SRC="$NDK_SYSROOT/usr/lib/$ANDROID_TRIPLE/libc++_shared.so"
if [ ! -f "$LIBCPP_SRC" ]; then
    echo "ERROR: libc++_shared.so not found at $LIBCPP_SRC"
    exit 1
fi
cp "$LIBCPP_SRC" "$PKG_DIR/libc++_shared.so"
echo "    $(stat -c%s "$PKG_DIR/libc++_shared.so") bytes"

echo ">>> Copying libopentui.so (both opentui asset keys)..."
mkdir -p "$PKG_DIR/opentui-assets/@opentui/core-linux-arm64" \
         "$PKG_DIR/opentui-assets/@opentui/core-linux-x64"
cp "$ARM64_SO" "$PKG_DIR/opentui-assets/@opentui/core-linux-arm64/libopentui.so"
cp "$ARM64_SO" "$PKG_DIR/opentui-assets/@opentui/core-linux-x64/libopentui.so"

# Optional Android/Bionic pty library.
PTY_ADDED=""
for candidate in \
    "$DIST_DIR/librust_pty_arm64.so" \
    "$OPENCODE_SRC/node_modules/bun-pty/rust-pty/target/release/librust_pty_arm64.so"
do
    if [ -f "$candidate" ]; then
        if readelf -d "$candidate" 2>/dev/null | grep 'Shared library:' | grep -Eq 'libc\.so\.6|libpthread\.so\.0|libutil\.so\.1'; then
            echo ">>> Skipping glibc-linked $candidate"
            break
        fi
        cp "$candidate" "$PKG_DIR/librust_pty_arm64.so"
        PTY_ADDED="librust_pty_arm64.so"
        echo ">>> Included librust_pty_arm64.so"
        break
    fi
done
if [ -z "$PTY_ADDED" ]; then
    echo ">>> No Android librust_pty_arm64.so; PTY (terminal) disabled"
fi

cp "$OPENCODE_BINARY" "$PKG_DIR/opencode.bin"
cp "$PARSER_WORKER" "$PKG_DIR/parser.worker.js"
cp "$WRAPPER_SCRIPT" "$PKG_DIR/opencode"
chmod 755 "$PKG_DIR/opencode" "$PKG_DIR/opencode.bin"

# ==========================================
# 1. ZIP package (flat layout)
# ==========================================
echo ">>> Creating ZIP package..."
ZIP_NAME="opencode-${OPENCODE_VERSION}-android-aarch64.zip"
cd "$PKG_DIR"
ZIP_FILES="opencode opencode.bin parser.worker.js libtagfix.so libc++_shared.so opentui-assets"
[ -n "$PTY_ADDED" ] && ZIP_FILES="$ZIP_FILES $PTY_ADDED"
rm -f "$PKG_DIR/$ZIP_NAME"
zip -9 -r "$PKG_DIR/$ZIP_NAME" $ZIP_FILES >/dev/null
echo "    Created $ZIP_NAME"

# ==========================================
# 2. Pacman package (Termux)
# ==========================================
echo ">>> Creating pacman package..."
PACMAN_USR="$PKG_DIR/pacman-staging/data/data/com.termux/files/usr"
mkdir -p "$PACMAN_USR/bin" "$PACMAN_USR/libexec/opencode" "$PACMAN_USR/lib"
cp "$WRAPPER_SCRIPT" "$PACMAN_USR/bin/opencode"
cp "$OPENCODE_BINARY" "$PACMAN_USR/libexec/opencode/opencode.bin"
cp "$PARSER_WORKER" "$PACMAN_USR/libexec/opencode/parser.worker.js"
cp "$PKG_DIR/libtagfix.so" "$PACMAN_USR/lib/libtagfix.so"
cp "$PKG_DIR/libc++_shared.so" "$PACMAN_USR/lib/libc++_shared.so"
cp -a "$PKG_DIR/opentui-assets" "$PACMAN_USR/lib/opentui-assets"
[ -n "$PTY_ADDED" ] && cp "$PKG_DIR/librust_pty_arm64.so" "$PACMAN_USR/lib/librust_pty_arm64.so"
chmod 755 "$PACMAN_USR/bin/opencode" "$PACMAN_USR/libexec/opencode/opencode.bin"

cat > "$PKG_DIR/pacman-staging/.PKGINFO" << EOF
pkgname = opencode
pkgver = ${OPENCODE_VERSION}-1
pkgdesc = AI-powered coding assistant for the terminal
url = https://github.com/anomalyco/opencode
builddate = ${BUILD_DATE}
packager = opencode-termux
size = $((BINARY_SIZE / 1024))
arch = aarch64
license = MIT
depend = ripgrep
EOF

PACMAN_NAME="opencode-${OPENCODE_VERSION}-1-aarch64.pkg.tar.xz"
cd "$PKG_DIR/pacman-staging"
tar cf - .PKGINFO data | xz -9 > "$PKG_DIR/$PACMAN_NAME"
echo "    Created $PACMAN_NAME"

# ==========================================
# 3. Deb package (old Termux format)
# ==========================================
echo ">>> Creating deb package..."
DEB_USR="$PKG_DIR/deb-staging/data/data/data/com.termux/files/usr"
mkdir -p "$DEB_USR/bin" "$DEB_USR/libexec/opencode" "$DEB_USR/lib" "$PKG_DIR/deb-staging/DEBIAN"
cp "$WRAPPER_SCRIPT" "$DEB_USR/bin/opencode"
cp "$OPENCODE_BINARY" "$DEB_USR/libexec/opencode/opencode.bin"
cp "$PARSER_WORKER" "$DEB_USR/libexec/opencode/parser.worker.js"
cp "$PKG_DIR/libtagfix.so" "$DEB_USR/lib/libtagfix.so"
cp "$PKG_DIR/libc++_shared.so" "$DEB_USR/lib/libc++_shared.so"
cp -a "$PKG_DIR/opentui-assets" "$DEB_USR/lib/opentui-assets"
[ -n "$PTY_ADDED" ] && cp "$PKG_DIR/librust_pty_arm64.so" "$DEB_USR/lib/librust_pty_arm64.so"
chmod 755 "$DEB_USR/bin/opencode" "$DEB_USR/libexec/opencode/opencode.bin"

cat > "$PKG_DIR/deb-staging/DEBIAN/control" << EOF
Package: opencode
Version: ${OPENCODE_VERSION}
Architecture: aarch64
Maintainer: Guy Sheffer <guysoft@gmail.com>
Installed-Size: $((BINARY_SIZE / 1024))
Depends: ripgrep
Section: utils
Priority: optional
Homepage: https://github.com/anomalyco/opencode
Description: AI-powered coding assistant for the terminal
 OpenCode is an AI-powered coding assistant that runs in the terminal.
 This package provides a standalone binary compiled for Android/Termux.
EOF

DEB_NAME="opencode_${OPENCODE_VERSION}_aarch64.deb"
cd "$PKG_DIR/deb-staging/data"
tar czf "$PKG_DIR/deb-staging/data.tar.gz" data
cd "$PKG_DIR/deb-staging/DEBIAN"
tar czf "$PKG_DIR/deb-staging/control.tar.gz" control
echo "2.0" > "$PKG_DIR/deb-staging/debian-binary"
cd "$PKG_DIR/deb-staging"
ar rc "$PKG_DIR/$DEB_NAME" debian-binary control.tar.gz data.tar.gz
echo "    Created $DEB_NAME"

# ==========================================
# Summary
# ==========================================
echo ""
echo "=== Packages created ==="
ls -lh "$PKG_DIR"/*.zip "$PKG_DIR"/*.xz "$PKG_DIR"/*.deb 2>/dev/null
echo ""
echo "ZIP layout: opencode + opencode.bin + parser.worker.js + libtagfix.so"
echo "            + libc++_shared.so + opentui-assets/"
echo "Install (requires: ripgrep):"
echo "  pacman: pacman -U $PACMAN_NAME"
echo "  deb:    dpkg -i $DEB_NAME"
echo "  zip:    unzip $ZIP_NAME -d \$PREFIX/bin/"
