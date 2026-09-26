#!/usr/bin/env bash
# Build OpenCode standalone binary for Android aarch64
#
# Usage: ./scripts/build-opencode.sh
#
# This script:
# 1. Clones OpenCode if needed
# 2. Swaps x86_64 libopentui.so with ARM64 version
# 3. Runs the TypeScript build script to create the standalone binary
# 4. Restores original libopentui.so
#
# Requires:
# - Android Bun binary built (scripts/build-bun.sh)
# - libopentui.so built (scripts/build-opentui.sh)
# - Host Bun installed (for bundling)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

HOST_BUN="${HOST_BUN:-bun}"

echo "=== Building OpenCode v${OPENCODE_VERSION} for Android aarch64 ==="

# Clone OpenCode if needed
if [ ! -d "$OPENCODE_SRC/.git" ]; then
    echo ">>> Cloning OpenCode..."
    git clone --depth 1 --branch "v${OPENCODE_VERSION}" https://github.com/anomalyco/opencode.git "$OPENCODE_SRC"
else
    echo ">>> OpenCode source exists at $OPENCODE_SRC"
fi

# Apply Android patches to the OpenCode source tree (Termux compatibility
# fixes that upstream does not carry). New patches go in patches/opencode/.
OPENCODE_PATCH_DIR="$REPO_ROOT/patches/opencode"
if [ -d "$OPENCODE_PATCH_DIR" ]; then
    echo ">>> Applying OpenCode Android patches..."
    cd "$OPENCODE_SRC"
    for p in "$OPENCODE_PATCH_DIR"/*.patch; do
        [ -f "$p" ] || continue
        if git apply --check "$p" 2>/dev/null; then
            git apply "$p"
            echo "    Applied $(basename "$p")"
        else
            echo "    Skipping $(basename "$p") (already applied or does not apply)"
        fi
    done
fi

OPENCODE_PKG="$OPENCODE_SRC/packages/opencode"

# Install OpenCode dependencies
echo ">>> Installing OpenCode dependencies..."
cd "$OPENCODE_SRC"
"$HOST_BUN" install

# Install native packages for ALL platforms (not just the host).
# The phone is linux/arm64 but the build host is linux/x64: without this,
# node_modules contains only @opentui/core-linux-x64 (plus watcher/fff x64
# binaries), so the bundle embeds no ARM64 native assets and the TUI crashes
# on device (undefined native library path). Same as upstream script/build.ts.
echo ">>> Installing native packages for all platforms..."
OPENTUI_VER="$("$HOST_BUN" -e 'console.log(require("./package.json").workspaces.catalog["@opentui/core"])')"
WATCHER_VER="$("$HOST_BUN" -e 'console.log(require("./packages/opencode/package.json").dependencies["@parcel/watcher"])')"
FFF_VER="$("$HOST_BUN" -e 'console.log(require("./packages/opencode/package.json").dependencies["@ff-labs/fff-bun"])')"
echo "    @opentui/core@${OPENTUI_VER}, @parcel/watcher@${WATCHER_VER}, @ff-labs/fff-bun@${FFF_VER}"
"$HOST_BUN" install --os="*" --cpu="*" \
    "@opentui/core@${OPENTUI_VER}" \
    "@parcel/watcher@${WATCHER_VER}" \
    "@ff-labs/fff-bun@${FFF_VER}"

# Find the Android bun binary
ANDROID_BUN="$BUN_BUILD/bun"
if [ ! -f "$ANDROID_BUN" ]; then
    echo "ERROR: Android bun binary not found at $ANDROID_BUN"
    echo "       Run scripts/build-bun.sh first."
    exit 1
fi

# Find ARM64 libopentui.so (layout differs by opentui version).
#   pre-0.5 (v0.4.5): packages/core/src/lib/aarch64-linux-android/libopentui.so
#   0.5+:             packages/lib/aarch64-linux-android/libopentui.so
ARM64_LIBOPENTUI=""
for candidate in \
    "$OPENTUI_SRC/packages/core/src/lib/aarch64-linux-android/libopentui.so" \
    "$OPENTUI_SRC/packages/lib/aarch64-linux-android/libopentui.so"
do
    if [ -f "$candidate" ]; then
        ARM64_LIBOPENTUI="$candidate"
        break
    fi
done
if [ -z "$ARM64_LIBOPENTUI" ]; then
    ARM64_LIBOPENTUI="$(find "$OPENTUI_SRC" -path "*aarch64-linux-android/libopentui.so" -type f 2>/dev/null | head -n 1 || true)"
fi
if [ ! -f "$ARM64_LIBOPENTUI" ]; then
    echo "ERROR: ARM64 libopentui.so not found at $ARM64_LIBOPENTUI"
    echo "       Run scripts/build-opentui.sh first."
    exit 1
fi

# Swap the prebuilt libopentui.so files in node_modules with our Android build.
# The phone (linux/arm64) loads @opentui/core-linux-arm64 at runtime; the x64
# copy is swapped too so any embedded/host reference stays consistent.
swap_libopentui() {
    local pkg="$1"   # e.g. @opentui/core-linux-x64
    # bun's isolated install dirs use '+' instead of '/' in package names
    local pkg_bun="${pkg//\//+}"
    local found=""
    local candidate f
    for candidate in \
        "$OPENCODE_SRC/node_modules/${pkg}/libopentui.so" \
        "$OPENCODE_PKG/node_modules/${pkg}/libopentui.so" \
        "$OPENCODE_SRC/node_modules/.bun/${pkg_bun}@*/node_modules/${pkg}/libopentui.so"
    do
        # Handle glob
        for f in $candidate; do
            if [ -f "$f" ]; then
                found="$f"
                break 2
            fi
        done
    done
    if [ -z "$found" ]; then
        echo "WARNING: Could not find ${pkg}/libopentui.so in node_modules"
        return 0
    fi
    echo ">>> Swapping ${pkg}/libopentui.so with Android ARM64 version..."
    cp "$found" "${found}.x64.bak"
    cp "$ARM64_LIBOPENTUI" "$found"
    echo "$found" >> "$SWAP_LIST"
}

SWAP_LIST="$(mktemp)"
DIST_LIST="$(mktemp)"
restore_libopentui() {
    # Idempotent: safe to run twice (explicit call + EXIT trap).
    if [ -s "$SWAP_LIST" ]; then
        while IFS= read -r swapped; do
            if [ -f "${swapped}.x64.bak" ]; then
                mv "${swapped}.x64.bak" "$swapped"
            fi
        done < "$SWAP_LIST"
    fi
    rm -f "$SWAP_LIST"
    if [ -s "$DIST_LIST" ]; then
        while IFS= read -r patched; do
            if [ -f "${patched}.termux-bak" ]; then
                mv "${patched}.termux-bak" "$patched"
            fi
        done < "$DIST_LIST"
    fi
    rm -f "$DIST_LIST"
}
trap restore_libopentui EXIT
swap_libopentui "@opentui/core-linux-arm64"
swap_libopentui "@opentui/core-linux-x64"
if [ ! -s "$SWAP_LIST" ]; then
    echo "WARNING: No libopentui.so found to swap - the build may embed the wrong architecture"
fi

# Link non-host platform packages into @opentui/core's isolated scope.
# bun install links only the HOST platform's optionals next to @opentui/core,
# so Bun.build cannot resolve import("@opentui/core-linux-arm64") and leaves
# it external -> the TUI crashes on the phone with an undefined library path.
# Symlinking the store copies into the scope makes the import bundlable.
echo ">>> Linking platform packages into @opentui/core scope..."
for scope in "$OPENCODE_SRC"/node_modules/.bun/@opentui+core@*/node_modules/@opentui; do
    [ -d "$scope" ] || continue
    for plat_store in "$OPENCODE_SRC"/node_modules/.bun/@opentui+core-linux-*@/node_modules/@opentui \
                      "$OPENCODE_SRC"/node_modules/.bun/@opentui+core-linux-*@*/node_modules/@opentui; do
        [ -d "$plat_store" ] || continue
        for pkg_dir in "$plat_store"/*; do
            [ -d "$pkg_dir" ] || continue
            pkg_name="$(basename "$pkg_dir")"
            if [ ! -e "$scope/$pkg_name" ]; then
                ln -s "$pkg_dir" "$scope/$pkg_name"
                echo "    linked $pkg_name"
            fi
        done
    done
done

# Patch @opentui/core's asset loader for the standalone binary.
#
# Two fixes, both required:
#  1. resolveAssetRootPath() THROWS when a key is absent under
#     OTUI_ASSET_ROOT. We set that root to point the loader at the ARM64
#     libopentui.so we ship as a real file (bare package imports do not
#     resolve inside the standalone), so any other asset lookup
#     (tree-sitter wasm/scm) would hard-fail. Return undefined instead and
#     let those fall back to their normal handling.
#  2. The tree-sitter parser worker resolves via
#     import("@opentui/core/parser.worker", { type: "file" }), which yields a
#     module with NO default export in this build, so
#     normalizeLoadedFilePath(undefined) throws at module load:
#     "undefined is not an object (evaluating 'loadedPath.startsWith')".
#     Return undefined for undefined input; the worker path is then supplied
#     at runtime via OTUI_TREE_SITTER_WORKER_PATH (checked first by
#     resolveWorkerPath()).
echo ">>> Patching OpenTUI asset loader for standalone..."
# NOTE: in the published npm package the chunks sit directly in
# @opentui/core/ (no dist/ subdirectory).
while IFS= read -r chunk; do
    if grep -q "Missing OpenTUI asset" "$chunk"; then
        cp "$chunk" "${chunk}.termux-bak"
        echo "$chunk" >> "$DIST_LIST"
        sed -i 's/throw new Error(`Missing OpenTUI asset.*/return;/' "$chunk"
        sed -i '/^function normalizeLoadedFilePath(loadedPath, baseUrl) {$/a\  if (loadedPath === undefined) return;' "$chunk"
        echo "    patched $(basename "$chunk")"
    fi
done < <(find "$OPENCODE_SRC/node_modules" -path "*@opentui/core/chunk-*.js" -type f 2>/dev/null)

# Fail loudly if the patches did not land: without them the TUI crashes at
# startup, which is worse than a red CI run.
if find "$OPENCODE_SRC/node_modules" -path "*@opentui/core/chunk-*.js" -type f \
        -exec grep -l "Missing OpenTUI asset" {} + 2>/dev/null | grep -q .; then
    echo "ERROR: OpenTUI asset-loader patch did not apply."
    echo "       Upstream chunk changed; update the seds above."
    exit 1
fi
if ! grep -rq "if (loadedPath === undefined) return;" "$OPENCODE_SRC/node_modules/.bun"/@opentui+core@*/node_modules/@opentui/core/chunk-bun-*.js 2>/dev/null; then
    echo "ERROR: OpenTUI normalizeLoadedFilePath guard did not apply."
    exit 1
fi

# NOTE: @opentui/core resolves its parser worker (tree-sitter) and native
# library through file assets. Those are set up in scripts/build-opencode-android.ts
# (files/entrypoints/define), mirroring upstream script/build.ts.

# Create dist directory
mkdir -p "$DIST_DIR"

# Run the TypeScript build script
# Copy it into the OpenCode tree so Bun can resolve @opentui/solid/bun-plugin
# from node_modules (Bun resolves bare imports relative to the script file's location)
echo ">>> Building OpenCode standalone binary..."
BUILD_SCRIPT="$REPO_ROOT/scripts/build-opencode-android.ts"
BUILD_SCRIPT_LOCAL="$OPENCODE_PKG/build-opencode-android.ts"
cp "$BUILD_SCRIPT" "$BUILD_SCRIPT_LOCAL"
cd "$OPENCODE_PKG"

OPENCODE_VERSION="$OPENCODE_VERSION" \
    ANDROID_BUN="$ANDROID_BUN" \
    OUTPUT_DIR="$DIST_DIR" \
    OPENCODE_DIR="$OPENCODE_PKG" \
    "$HOST_BUN" run "$BUILD_SCRIPT_LOCAL"

# Clean up copied script
rm -f "$BUILD_SCRIPT_LOCAL"

# Restore original libopentui.so files (also runs via EXIT trap on failure)
restore_libopentui
echo ">>> Restored original libopentui.so files"

# Ship the tree-sitter parser worker as a real file. The standalone cannot
# resolve it through import("@opentui/core/parser.worker", { type: "file" })
# (module without default export), so the launcher points
# OTUI_TREE_SITTER_WORKER_PATH at this copy instead. Packages pick it up from
# DIST_DIR.
PARSER_WORKER="$(find "$OPENCODE_SRC/node_modules" -path "*@opentui/core/parser.worker.js" -type f 2>/dev/null | head -1)"
if [ -z "$PARSER_WORKER" ]; then
    echo "ERROR: parser.worker.js not found in $OPENCODE_SRC/node_modules"
    exit 1
fi
cp "$PARSER_WORKER" "$DIST_DIR/parser.worker.js"
echo ">>> Parser worker shipped: $PARSER_WORKER"

# Verify output
OPENCODE_BINARY="$DIST_DIR/opencode"
if [ ! -f "$OPENCODE_BINARY" ]; then
    echo "ERROR: OpenCode binary not found at $OPENCODE_BINARY"
    exit 1
fi

echo ""
echo "=== OpenCode build complete ==="
echo "Binary: $OPENCODE_BINARY"
echo "Size: $(du -h "$OPENCODE_BINARY" | cut -f1)"
file "$OPENCODE_BINARY"
