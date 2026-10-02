#!/usr/bin/env bash
# Bootstrap the opencode-termux installer.
# Downloads install-termux.sh and runs it.
set -euo pipefail

curl -fsSL https://raw.githubusercontent.com/re200484/opencode-termux/main/scripts/install-termux.sh -o install-opencode.sh
bash install-opencode.sh
