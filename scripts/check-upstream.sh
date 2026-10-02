#!/usr/bin/env bash
# Check whether upstream OpenCode has a release newer than our pinned version.
#
# Usage: ./scripts/check-upstream.sh
#   UPSTREAM_REPO=anomalyco/opencode ./scripts/check-upstream.sh
#   UPSTREAM_VERSION_OVERRIDE=1.18.33 ./scripts/check-upstream.sh
#
# Prints KEY=value lines (UPSTREAM_VERSION, CURRENT_VERSION, UPDATE_NEEDED),
# and appends them to $GITHUB_OUTPUT when running in GitHub Actions.
# Exit status is always 0; the answer is in UPDATE_NEEDED (yes/no).
#
# NOTE: the pinned version is read from .github/workflows/build.yml, which is
# the source of truth for CI. When bumping, update the OPENCODE_VERSION
# default in scripts/env.sh as well.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

UPSTREAM_REPO="${UPSTREAM_REPO:-anomalyco/opencode}"

if [ -n "${UPSTREAM_VERSION_OVERRIDE:-}" ]; then
    echo ">>> Using overridden upstream version: $UPSTREAM_VERSION_OVERRIDE"
    LATEST="$(printf '%s' "$UPSTREAM_VERSION_OVERRIDE" | sed -e 's/^v//')"
else
    echo ">>> Fetching latest $UPSTREAM_REPO release..."
    LATEST="$(curl -fsSL --retry 3 "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" \
        | grep -oE '"tag_name": *"[^"]+"' | head -1 \
        | sed -e 's/.*"tag_name": *"//' -e 's/^v//' -e 's/"$//')"
fi

CURRENT="$(grep -E '^\s*OPENCODE_VERSION:' "$REPO_ROOT/.github/workflows/build.yml" | head -1 \
    | sed -e 's/.*OPENCODE_VERSION: *//' -e 's/["'\'']//g' -e 's/ *$//')"

if [ -z "$LATEST" ]; then
    echo "ERROR: could not determine upstream version" >&2
    exit 1
fi
if [ -z "$CURRENT" ]; then
    echo "ERROR: could not determine pinned version from build.yml" >&2
    exit 1
fi

UPDATE_NEEDED=no
if [ "$LATEST" != "$CURRENT" ]; then
    NEWEST="$(printf '%s\n%s\n' "$CURRENT" "$LATEST" | sort -V | tail -1)"
    if [ "$NEWEST" = "$LATEST" ]; then
        UPDATE_NEEDED=yes
    fi
fi

echo "UPSTREAM_VERSION=$LATEST"
echo "CURRENT_VERSION=$CURRENT"
echo "UPDATE_NEEDED=$UPDATE_NEEDED"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "UPSTREAM_VERSION=$LATEST"
        echo "CURRENT_VERSION=$CURRENT"
        echo "UPDATE_NEEDED=$UPDATE_NEEDED"
    } >> "$GITHUB_OUTPUT"
fi
