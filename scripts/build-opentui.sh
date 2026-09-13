#!/usr/bin/env bash
# Build libopentui.so for Android aarch64
#
# Usage: ./scripts/build-opentui.sh
#
# OpenCode's TUI renderer (@opentui/core) uses a native Zig library.
# The upstream build targets aarch64-linux (musl), which fails on Android
# because getauxval cannot be resolved. We build for aarch64-linux-android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

ZIG_BIN="${ZIG_BIN:-zig}"

echo "=== Building libopentui.so for Android aarch64 ==="

# Clone opentui if needed, pinned to a tag compatible with this OpenCode version.
# NOTE: upstream restructured after v0.4.5 (build.zig moved from
# packages/core/src/zig to packages/native, -Dtarget renamed to
# -Dlibrary-target, Zig 0.15.2 -> 0.16.0). An unpinned `git clone --depth 1`
# pulls main and breaks this script, so always clone/checkout OPENTUI_VERSION
# (default v0.4.5, matches OpenCode 1.18.30's @opentui/core 0.4.5).
if [ ! -d "$OPENTUI_SRC/.git" ]; then
    echo ">>> Cloning opentui ($OPENTUI_VERSION)..."
    git clone --depth 1 --branch "$OPENTUI_VERSION" https://github.com/anomalyco/opentui.git "$OPENTUI_SRC"
else
    echo ">>> opentui source exists at $OPENTUI_SRC, ensuring $OPENTUI_VERSION..."
    cd "$OPENTUI_SRC"
    git fetch --tags --depth 1 origin "refs/tags/$OPENTUI_VERSION:refs/tags/$OPENTUI_VERSION" 2>/dev/null || true
    git checkout -q "$OPENTUI_VERSION" 2>/dev/null || echo "    WARNING: could not checkout $OPENTUI_VERSION, using existing checkout ($(git rev-parse --short HEAD 2>/dev/null || echo unknown))"
fi

# Apply Android libc linking patch
# Without this patch, the .so won't have NEEDED: libc.so, and Android's
# dlopen() will fail because it can't resolve symbols like getauxval.
OPENTUI_PATCH="$REPO_ROOT/patches/opentui/android-libc-link.patch"
if [ -f "$OPENTUI_PATCH" ]; then
    echo ">>> Applying opentui Android patch..."
    cd "$OPENTUI_SRC"
    if ! git apply --check "$OPENTUI_PATCH" 2>/dev/null; then
        echo "    Patch already applied or does not apply cleanly, skipping"
    else
        git apply "$OPENTUI_PATCH"
        echo "    Patch applied successfully"
    fi
fi

# Locate build.zig (layout changed upstream after v0.4.5).
OPENTUI_ZIG_DIR=""
ZIG_TARGET_FLAG="-Dtarget"
if [ -f "$OPENTUI_SRC/packages/core/src/zig/build.zig" ]; then
    OPENTUI_ZIG_DIR="$OPENTUI_SRC/packages/core/src/zig"
    ZIG_TARGET_FLAG="-Dtarget"
elif [ -f "$OPENTUI_SRC/packages/native/build.zig" ]; then
    echo "WARNING: opentui checkout uses new layout (packages/native)."
    echo "         OPENTUI_VERSION=$OPENTUI_VERSION was expected to use packages/core/src/zig."
    echo "         Continuing with new layout; if the build fails, set OPENTUI_VERSION=v0.4.5."
    OPENTUI_ZIG_DIR="$OPENTUI_SRC/packages/native"
    ZIG_TARGET_FLAG="-Dlibrary-target"
fi

if [ -z "$OPENTUI_ZIG_DIR" ] || [ ! -f "$OPENTUI_ZIG_DIR/build.zig" ]; then
    echo "ERROR: build.zig not found in opentui checkout ($OPENTUI_SRC)"
    echo "  Checked:"
    echo "    - $OPENTUI_SRC/packages/core/src/zig/build.zig (pre-0.5 layout)"
    echo "    - $OPENTUI_SRC/packages/native/build.zig (0.5+ layout)"
    echo "  Checked-out version: $(git -C "$OPENTUI_SRC" describe --tags --always 2>/dev/null || echo unknown)"
    exit 1
fi

echo ">>> Building with Zig in $OPENTUI_ZIG_DIR (flag: $ZIG_TARGET_FLAG=aarch64-linux-android)..."
cd "$OPENTUI_ZIG_DIR"

# NOTE: no --sysroot here. The NDK sysroot is wired inside build.zig itself
# (generated libc.txt, see patches/opentui/android-libc-link.patch): passing
# --sysroot on top of that makes lld resolve -L paths against the sysroot
# and breaks absolute NDK paths.
"$ZIG_BIN" build \
    "$ZIG_TARGET_FLAG=aarch64-linux-android" \
    -Doptimize=ReleaseSafe \
    --prefix . 2>&1

# The build.zig installs to dest_dir="../lib/{output_name}" relative to
# the --prefix dir.
#   old layout (--prefix=packages/core/src/zig): packages/core/src/lib/aarch64-linux-android/
#   new layout (--prefix=packages/native):      packages/lib/aarch64-linux-android/
LIBOPENTUI="$OPENTUI_ZIG_DIR/../lib/aarch64-linux-android/libopentui.so"
if [ ! -f "$LIBOPENTUI" ]; then
    # Fall back to a search: cover both layouts and any future output dir change.
    echo "  Not at expected path ($LIBOPENTUI), searching tree..."
    FOUND="$(find "$OPENTUI_SRC" -path "*aarch64-linux-android/libopentui.so" -type f 2>/dev/null | head -n 1 || true)"
    if [ -n "$FOUND" ]; then
        LIBOPENTUI="$FOUND"
    fi
fi
if [ ! -f "$LIBOPENTUI" ]; then
    echo "ERROR: libopentui.so not found"
    echo "  Expected at: $LIBOPENTUI"
    echo "  Searching for any libopentui.so under opentui-src..."
    find "$OPENTUI_SRC" -name "libopentui.so" -type f 2>/dev/null || true
    exit 1
fi

echo ""
echo "=== libopentui.so build complete ==="
echo "Output: $LIBOPENTUI"
echo "Size: $(du -h "$LIBOPENTUI" | cut -f1)"
file "$LIBOPENTUI"

# Verify the .so has NEEDED: libc.so (required for Android dlopen)
if readelf -d "$LIBOPENTUI" 2>/dev/null | grep -q "NEEDED.*libc.so"; then
    echo "OK: libopentui.so has NEEDED: libc.so (required for Android)"
else
    echo "ERROR: libopentui.so is missing NEEDED: libc.so dependency"
    echo "       Android dlopen() will fail without this."
    echo "       Ensure ANDROID_NDK_HOME is set and the opentui patch was applied."
    readelf -d "$LIBOPENTUI" 2>/dev/null | grep NEEDED || echo "       (no NEEDED entries found)"
    exit 1
fi
