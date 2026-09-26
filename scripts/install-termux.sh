#!/data/data/com.termux/files/usr/bin/bash
#
# opencode-termux installer for Termux / Android aarch64
#
# - cleans any previous install
# - finds the latest GitHub release of re200484/opencode-termux
# - asks whether to install the .deb package or the standalone .zip
# - installs dependencies only when missing
# - removes the downloaded file after a successful install
#
# Languages: en (default), es, it.
#   OPENCODE_LANG=es bash install-opencode.sh
#
set -euo pipefail

REPO="re200484/opencode-termux"
API="https://api.github.com/repos/${REPO}/releases/latest"

: "${PREFIX:=/data/data/com.termux/files/usr}"

LANG_CODE="${OPENCODE_LANG:-en}"
case "$LANG_CODE" in
    en|es|it) ;;
    *) LANG_CODE="en" ;;
esac

# ------------------------------------------------------------------ i18n
t() {
    local key="$1"; shift || true
    local fmt
    case "$key" in
        title) case "$LANG_CODE" in
            en) fmt="OpenCode installer for Termux (Android aarch64)" ;;
            es) fmt="Instalador de OpenCode para Termux (Android aarch64)" ;;
            it) fmt="Installer di OpenCode per Termux (Android aarch64)" ;;
        esac ;;
        lang_note) case "$LANG_CODE" in
            en) fmt="Language: English (default). Available: en, es, it. To use another language, run:  OPENCODE_LANG=es bash install-opencode.sh" ;;
            es) fmt="Idioma: ingles (predeterminado). Disponibles: en, es, it. Para usar otro idioma, ejecuta:  OPENCODE_LANG=es bash install-opencode.sh" ;;
            it) fmt="Lingua: inglese (predefinita). Disponibili: en, es, it. Per usare un'altra lingua, esegui:  OPENCODE_LANG=es bash install-opencode.sh" ;;
        esac ;;
        searching) case "$LANG_CODE" in
            en) fmt="Looking for the latest release of %s ..." ;;
            es) fmt="Buscando la ultima version de %s ..." ;;
            it) fmt="Cerco l'ultima release di %s ..." ;;
        esac ;;
        release_found) case "$LANG_CODE" in
            en) fmt="Latest release: %s" ;;
            es) fmt="Ultima version: %s" ;;
            it) fmt="Ultima release: %s" ;;
        esac ;;
        no_github) case "$LANG_CODE" in
            en) fmt="Cannot reach GitHub (rate limit?). Try again in a few minutes." ;;
            es) fmt="No se puede contactar con GitHub (limite de peticiones?). Intenta de nuevo en unos minutos." ;;
            it) fmt="Impossibile contattare GitHub (rate limit?). Riprova tra qualche minuto." ;;
        esac ;;
        asset_missing) case "$LANG_CODE" in
            en) fmt="Asset %s not found in the latest release." ;;
            es) fmt="No se encontro el asset %s en la ultima version." ;;
            it) fmt="Asset %s non trovato nell'ultima release." ;;
        esac ;;
        cleanup) case "$LANG_CODE" in
            en) fmt="Removing previous install..." ;;
            es) fmt="Eliminando la instalacion anterior..." ;;
            it) fmt="Rimuovo l'installazione precedente..." ;;
        esac ;;
        dep_installing) case "$LANG_CODE" in
            en) fmt="Installing missing package: %s" ;;
            es) fmt="Instalando paquete que falta: %s" ;;
            it) fmt="Installo pacchetto mancante: %s" ;;
        esac ;;
        choice_title) case "$LANG_CODE" in
            en) fmt="How do you want to install OpenCode %s ?" ;;
            es) fmt="Como quieres instalar OpenCode %s ?" ;;
            it) fmt="Come vuoi installare OpenCode %s ?" ;;
        esac ;;
        choice_deb) case "$LANG_CODE" in
            en) fmt="  1) deb  - Termux package (needs libc++ and ripgrep)" ;;
            es) fmt="  1) deb  - paquete de Termux (necesita libc++ y ripgrep)" ;;
            it) fmt="  1) deb  - pacchetto Termux (richiede libc++ e ripgrep)" ;;
        esac ;;
        choice_zip) case "$LANG_CODE" in
            en) fmt="  2) zip  - standalone, no extra dependencies" ;;
            es) fmt="  2) zip  - standalone, sin dependencias extra" ;;
            it) fmt="  2) zip  - standalone, nessuna dipendenza extra" ;;
        esac ;;
        choice_prompt) case "$LANG_CODE" in
            en) fmt="choice [1/2]: " ;;
            es) fmt="eleccion [1/2]: " ;;
            it) fmt="scelta [1/2]: " ;;
        esac ;;
        invalid_choice) case "$LANG_CODE" in
            en) fmt="Invalid choice: '%s'" ;;
            es) fmt="Eleccion no valida: '%s'" ;;
            it) fmt="Scelta non valida: '%s'" ;;
        esac ;;
        downloading) case "$LANG_CODE" in
            en) fmt="Downloading %s ..." ;;
            es) fmt="Descargando %s ..." ;;
            it) fmt="Scarico %s ..." ;;
        esac ;;
        installing_dpkg) case "$LANG_CODE" in
            en) fmt="Installing with dpkg..." ;;
            es) fmt="Instalando con dpkg..." ;;
            it) fmt="Installo con dpkg..." ;;
        esac ;;
        installing_flat) case "$LANG_CODE" in
            en) fmt="Installing (flat layout in \$PREFIX/bin)..." ;;
            es) fmt="Instalando (disposicion plana en \$PREFIX/bin)..." ;;
            it) fmt="Installo (layout flat in \$PREFIX/bin)..." ;;
        esac ;;
        removing_download) case "$LANG_CODE" in
            en) fmt="Removing the downloaded file..." ;;
            es) fmt="Eliminando el archivo descargado..." ;;
            it) fmt="Elimino il file scaricato..." ;;
        esac ;;
        done) case "$LANG_CODE" in
            en) fmt="Done." ;;
            es) fmt="Hecho." ;;
            it) fmt="Fatto." ;;
        esac ;;
        installed_version) case "$LANG_CODE" in
            en) fmt="Installed version: %s" ;;
            es) fmt="Version instalada: %s" ;;
            it) fmt="Versione installata: %s" ;;
        esac ;;
        tryit) case "$LANG_CODE" in
            en) fmt="Try:\n  opencode --version\n  opencode" ;;
            es) fmt="Prueba:\n  opencode --version\n  opencode" ;;
            it) fmt="Prova:\n  opencode --version\n  opencode" ;;
        esac ;;
        dpkg_missing) case "$LANG_CODE" in
            en) fmt="dpkg not found" ;;
            es) fmt="dpkg no encontrado" ;;
            it) fmt="dpkg non trovato" ;;
        esac ;;
        error) case "$LANG_CODE" in
            en) fmt="error: %s" ;;
            es) fmt="error: %s" ;;
            it) fmt="errore: %s" ;;
        esac ;;
        *) fmt="" ;;
    esac
    printf "$fmt\n" "$@"
}

say()  { printf '%s\n' "$*"; }
die()  { t error "$*" >&2; exit 1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
have_pkg() { dpkg -s "$1" >/dev/null 2>&1; }

# Install a package only if it is not already present.
#   ensure_cmd <command> <package>
ensure_cmd() {
    if have_cmd "$1"; then return 0; fi
    t dep_installing "$2"
    pkg install -y "$2"
}
#   ensure_pkg <package>
ensure_pkg() {
    if have_pkg "$1"; then return 0; fi
    t dep_installing "$1"
    pkg install -y "$1"
}
ensure_libcpp() {
    if have_pkg libc++ || [ -f "$PREFIX/lib/libc++_shared.so" ]; then return 0; fi
    t dep_installing "libc++"
    pkg install -y libc++
}

ask_choice() {
    printf '%s' "$(t choice_prompt)"
    if [ -r /dev/tty ]; then
        read -r CHOICE </dev/tty
    else
        read -r CHOICE
    fi
}

# ------------------------------------------------------------------- start
say "== $(t title) =="
say "$(t lang_note)"
say ""

ensure_cmd curl curl

say "$(t searching "$REPO")"
REL_JSON="$(curl -fsSL "$API" 2>/dev/null || true)"
[ -n "$REL_JSON" ] || die "$(t no_github)"

TAG="$(printf '%s' "$REL_JSON" | grep -oE '"tag_name": *"[^"]+"' | head -1 | sed 's/.*"tag_name": *"//; s/"$//')"
ZIP_URL="$(printf '%s' "$REL_JSON" | grep -oE '"browser_download_url": *"[^"]+android-aarch64\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')"
DEB_URL="$(printf '%s' "$REL_JSON" | grep -oE '"browser_download_url": *"[^"]+_aarch64\.deb"' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')"

[ -n "$TAG" ]     || die "$(t asset_missing "tag")"
[ -n "$ZIP_URL" ] || die "$(t asset_missing ".zip")"
[ -n "$DEB_URL" ] || die "$(t asset_missing ".deb")"
say "$(t release_found "$TAG")"

# ------------------------------------------------------------------ cleanup
say "$(t cleanup)"
dpkg --remove --force-remove-reinstreq opencode 2>/dev/null || true
rm -rf "$PREFIX/libexec/opencode" "$PREFIX/lib/opentui-assets"
rm -f  "$PREFIX/lib/libtagfix.so" "$PREFIX/lib/libopentui.so" "$PREFIX/lib/librust_pty_arm64.so"
# residues of a previous "flat" install in bin
rm -f  "$PREFIX/bin/opencode.bin" "$PREFIX/bin/parser.worker.js" \
       "$PREFIX/bin/libtagfix.so" "$PREFIX/bin/libc++_shared.so"
rm -rf "$PREFIX/bin/opentui-assets"

# ------------------------------------------------------------------- choice
say ""
say "$(t choice_title "$TAG")"
say "$(t choice_deb)"
say "$(t choice_zip)"
ask_choice

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

case "$CHOICE" in
    1|deb|DEB)
        have_cmd dpkg || die "$(t dpkg_missing)"
        ensure_libcpp
        ensure_cmd rg ripgrep
        t downloading "$DEB_URL"
        curl -fL --progress-bar "$DEB_URL" -o "$TMP_DIR/opencode.deb"
        t installing_dpkg
        dpkg -i "$TMP_DIR/opencode.deb"
        ;;
    2|zip|ZIP)
        ensure_cmd unzip unzip
        ensure_cmd rg ripgrep || true
        t downloading "$ZIP_URL"
        curl -fL --progress-bar "$ZIP_URL" -o "$TMP_DIR/opencode.zip"
        t installing_flat
        unzip -o "$TMP_DIR/opencode.zip" -d "$PREFIX/bin/"
        chmod +x "$PREFIX/bin/opencode" "$PREFIX/bin/opencode.bin"
        ;;
    *)
        die "$(t invalid_choice "$CHOICE")"
        ;;
esac

# Remove the downloaded archive after a successful install.
t removing_download
rm -rf "$TMP_DIR"
trap - EXIT

say ""
say "== $(t done) =="
say "$(t installed_version "$TAG")"
t tryit
