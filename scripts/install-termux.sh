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
GH="https://github.com/${REPO}"
# Bumped when the discovery logic changes, so a cached/stale copy is obvious in
# the debug line printed when release discovery fails.
INSTALLER_REV="2026-10-16d"
# Release discovery deliberately avoids api.github.com: anonymous API access is
# rate-limited to 60 requests/hour per IP, and shared/mobile (CGNAT) connections
# exhaust that easily, which made the installer fail with "cannot reach GitHub".
# We use the public releases.atom feed and the /releases/latest redirect instead.
#
# To install a specific release, bypass the menu:
#   OPENCODE_TAG=v1.19.2-android.1-rc.1 bash install-opencode.sh

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
            en) fmt="Cannot reach GitHub. Check your network connection and try again." ;;
            es) fmt="No se puede contactar con GitHub. Comprueba tu conexion e intentalo de nuevo." ;;
            it) fmt="Impossibile contattare GitHub. Controlla la connessione e riprova." ;;
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
        which_release) case "$LANG_CODE" in
            en) fmt="Which release do you want to install?" ;;
            es) fmt="¿Qué versión quieres instalar?" ;;
            it) fmt="Quale release vuoi installare?" ;;
        esac ;;
        rel_stable) case "$LANG_CODE" in
            en) fmt="%s (stable, tested)" ;;
            es) fmt="%s (estable, probada)" ;;
            it) fmt="%s (stabile, testata)" ;;
        esac ;;
        rel_try) case "$LANG_CODE" in
            en) fmt="%s (to try: validation build, please test it!)" ;;
            es) fmt="%s (para probar: compilación de validación, ¡pruébala!)" ;;
            it) fmt="%s (da provare: build di validazione, provala!)" ;;
        esac ;;
        rel_choice_prompt) case "$LANG_CODE" in
            en) fmt="release [1-%s] (default 1): " ;;
            es) fmt="versión [1-%s] (por defecto 1): " ;;
            it) fmt="release [1-%s] (predefinita 1): " ;;
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

# Read a line into $1 from the terminal. Falls back to stdin, and never lets a
# failed read abort the script under `set -e` (e.g. no controlling terminal).
read_answer() {
    local __var="$1" __val=""
    if { IFS= read -r __val </dev/tty; } 2>/dev/null; then
        :
    elif IFS= read -r __val 2>/dev/null; then
        :
    else
        __val=""
    fi
    printf -v "$__var" '%s' "$__val"
}

ask_choice() {
    printf '%s' "$(t choice_prompt)"
    read_answer CHOICE
}

# Release tag -> OpenCode version: v1.19.2-android.1-rc.1 -> 1.19.2
version_of() {
    printf '%s' "$1" | sed 's/^v//; s/-android\..*$//'
}
# Compare stable vs pre-release by their version (1.19.2 == 1.19.2).
base_of() {
    version_of "$1"
}
asset_zip_url() {
    printf '%s/releases/download/%s/opencode-%s-android-aarch64.zip' "$GH" "$1" "$(version_of "$1")"
}
asset_deb_url() {
    printf '%s/releases/download/%s/opencode_%s_aarch64.deb' "$GH" "$1" "$(version_of "$1")"
}
# All release tags, newest first, from the public Atom feed (no API, no rate
# limit). Pre-releases are identifiable by the -rc. suffix our tags use.
# NOTE: no awk/head in this pipeline — Termux does not ship awk by default, and
# `head` would close the pipe early (SIGPIPE under `set -o pipefail`). The feed
# lists each tag exactly once.
list_release_tags() {
    curl -fsSL "${GH}/releases.atom" 2>/dev/null \
        | grep -oE 'releases/tag/[^"<]+' \
        | sed 's#releases/tag/##'
}
# Cheap existence check so a wrong asset name fails with a clear message.
url_exists() {
    curl -fsIL --max-time 25 "$1" >/dev/null 2>&1
}

ask_release() {
    # $1 = number of menu entries. Sets REL_CHOICE (default 1).
    local max=$1
    printf '%s' "$(t rel_choice_prompt "$max")"
    read_answer REL_CHOICE
    : "${REL_CHOICE:=1}"
}

# ------------------------------------------------------------------- start
say "== $(t title) =="
say "$(t lang_note)"
say ""

ensure_cmd curl curl

say "$(t searching "$REPO")"

STABLE_TAG=""
RC_TAG=""
TAG="${OPENCODE_TAG:-}"
if [ -z "$TAG" ]; then
    TAGS=()
    while IFS= read -r _line; do
        if [ -n "$_line" ]; then TAGS+=("$_line"); fi
    done < <(list_release_tags)
    for _t in "${TAGS[@]}"; do
        case "$_t" in
            *-rc.*)
                if [ -z "$RC_TAG" ]; then RC_TAG="$_t"; fi
                ;;
            *)
                if [ -z "$STABLE_TAG" ]; then STABLE_TAG="$_t"; fi
                ;;
        esac
    done
    if [ -z "$STABLE_TAG" ]; then
        _http="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "${GH}/releases.atom" 2>/dev/null || true)"
        : "${_http:=curl-failed}"
        printf 'debug: installer rev %s; %s/releases.atom -> HTTP %s\n' "$INSTALLER_REV" "$GH" "$_http" >&2
        die "$(t no_github)"
    fi
    TAG="$STABLE_TAG"
fi

# Offer the newest validation pre-release next to the stable build, unless a
# tag was forced via OPENCODE_TAG or both point at the same version.
if [ -z "${OPENCODE_TAG:-}" ] && [ -n "$RC_TAG" ] && [ "$(base_of "$RC_TAG")" != "$(base_of "$TAG")" ]; then
    say ""
    say "$(t which_release)"
    say "  1) $(t rel_stable "$TAG")"
    say "  2) $(t rel_try "$RC_TAG")"
    ask_release 2
    case "${REL_CHOICE:-1}" in
        1) : ;;
        2) TAG="$RC_TAG" ;;
        *) die "$(t invalid_choice "$REL_CHOICE")" ;;
    esac
fi

ZIP_URL="$(asset_zip_url "$TAG")"
DEB_URL="$(asset_deb_url "$TAG")"

[ -n "$TAG" ]     || die "$(t asset_missing "tag")"
[ -n "$ZIP_URL" ] || die "$(t asset_missing ".zip")"
[ -n "$DEB_URL" ] || die "$(t asset_missing ".deb")"
if ! url_exists "$ZIP_URL"; then
    die "$(t asset_missing "$(printf '%s' "$ZIP_URL" | sed 's#.*/##')")"
fi
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
        mkdir -p "$PREFIX/bin"
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
