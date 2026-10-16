#!/usr/bin/env bash
# Bootstrap the opencode-termux installer.
# Downloads install-termux.sh and runs it.
set -euo pipefail

# Cache-busting query: raw.githubusercontent.com caches for a few minutes, and a
# stale copy would silently run the previous installer.
BASE="https://raw.githubusercontent.com/re200484/opencode-termux/main/scripts"

curl -fsSL "${BASE}/install-termux.sh?$(date +%s)" -o install-opencode.sh
bash install-opencode.sh
