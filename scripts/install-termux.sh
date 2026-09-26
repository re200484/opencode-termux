#!/data/data/com.termux/files/usr/bin/bash
#
# opencode-termux installer for Termux / Android aarch64
#
# Does a clean uninstall of any previous install, finds the latest GitHub
# release of re200484/opencode-termux, then asks whether to install the
# .deb package or the standalone .zip.
#
# Usage (on the device):
#   curl -fsSL https://raw.githubusercontent.com/re200484/opencode-termux/main/scripts/install-termux.sh -o install-opencode.sh
#   bash install-opencode.sh
#
set -euo pipefail

REPO="re200484/opencode-termux"
API="https://api.github.com/repos/${REPO}/releases/latest"

: "${PREFIX:=/data/data/com.termux/files/usr}"

say() { printf '%s\n' "$*"; }
die() { printf 'opencode installer: errore: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- dependencies
if ! command -v curl >/dev/null 2>&1; then
    say ">>> installo curl..."
    pkg install -y curl
fi

# ------------------------------------------------------------- latest release
say ">>> cerco l'ultima release di ${REPO}..."
REL_JSON="$(curl -fsSL "$API" 2>/dev/null || true)"
[ -n "$REL_JSON" ] || die "impossibile contattare GitHub (rate limit? riprova tra poco)"

TAG="$(printf '%s' "$REL_JSON" | grep -oE '"tag_name": *"[^"]+"' | head -1 | sed 's/.*"tag_name": *"//; s/"$//')"
ZIP_URL="$(printf '%s' "$REL_JSON" | grep -oE '"browser_download_url": *"[^"]+android-aarch64\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')"
DEB_URL="$(printf '%s' "$REL_JSON" | grep -oE '"browser_download_url": *"[^"]+_aarch64\.deb"' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')"

[ -n "$TAG" ]     || die "tag della release non trovato"
[ -n "$ZIP_URL" ] || die "asset .zip non trovato nella release $TAG"
[ -n "$DEB_URL" ] || die "asset .deb non trovato nella release $TAG"
say ">>> ultima release: $TAG"

# ------------------------------------------------------------------- cleanup
say ">>> pulizia installazione precedente..."
dpkg --remove --force-remove-reinstreq opencode 2>/dev/null || true
rm -rf "$PREFIX/libexec/opencode" "$PREFIX/lib/opentui-assets"
rm -f  "$PREFIX/lib/libtagfix.so" "$PREFIX/lib/libopentui.so" "$PREFIX/lib/librust_pty_arm64.so"
# residui di un'installazione "flat" nella bin
rm -f  "$PREFIX/bin/opencode.bin" "$PREFIX/bin/parser.worker.js" \
       "$PREFIX/bin/libtagfix.so" "$PREFIX/bin/libc++_shared.so"
rm -rf "$PREFIX/bin/opentui-assets"

# --------------------------------------------------------------------- choice
say ""
say "Come vuoi installare OpenCode $TAG ?"
say "  1) deb  - pacchetto Termux (dipende da libc++ e ripgrep)"
say "  2) zip  - standalone, nessuna dipendenza extra"
printf 'scelta [1/2]: '
read -r CHOICE

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

case "$CHOICE" in
    1|deb|DEB)
        command -v dpkg >/dev/null 2>&1 || die "dpkg non trovato"
        say ">>> installo dipendenze (libc++, ripgrep)..."
        pkg install -y libc++ ripgrep
        say ">>> scarico il pacchetto deb..."
        curl -fL --progress-bar "$DEB_URL" -o "$TMP_DIR/opencode.deb"
        say ">>> installo con dpkg..."
        dpkg -i "$TMP_DIR/opencode.deb"
        ;;
    2|zip|ZIP)
        command -v unzip >/dev/null 2>&1 || { say ">>> installo unzip..."; pkg install -y unzip; }
        say ">>> installo ripgrep (consigliato)..."
        pkg install -y ripgrep || true
        say ">>> scarico lo zip..."
        curl -fL --progress-bar "$ZIP_URL" -o "$TMP_DIR/opencode.zip"
        say ">>> installo (layout flat in \$PREFIX/bin)..."
        unzip -o "$TMP_DIR/opencode.zip" -d "$PREFIX/bin/"
        chmod +x "$PREFIX/bin/opencode" "$PREFIX/bin/opencode.bin"
        ;;
    *)
        die "scelta non valida: '$CHOICE'"
        ;;
esac

say ""
say "=== fatto ==="
say "Versione installata: $TAG"
say "Prova con:"
say "  opencode --version"
say "  opencode"
