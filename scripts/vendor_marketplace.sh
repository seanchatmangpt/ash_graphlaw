#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
#
# Materializes vendor/ggen-marketplace/packs/ash-extension-pack from the exact marketplace sha
# pinned in ontology.ttl (glx:marketplaceSha) with `git archive`; no clone, no worktree. The
# source repository defaults to ~/ggen-marketplace (override with GGEN_MARKETPLACE_REPO). The
# sha is recorded in vendor/ggen-marketplace/.pin and re-checked by scripts/ggen_sync.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

repo="${GGEN_MARKETPLACE_REPO:-$HOME/ggen-marketplace}"
sha=$(sed -n 's/.*glx:marketplaceSha "\([0-9a-f]\{40\}\)".*/\1/p' ontology.ttl | head -n1)
[ -n "$sha" ] || { echo "REFUSED(pin:absent glx:marketplaceSha)" >&2; exit 2; }

rm -rf vendor/ggen-marketplace
mkdir -p vendor/ggen-marketplace
git -C "$repo" archive "$sha" packs/ash-extension-pack | tar -x -C vendor/ggen-marketplace
printf '%s\n' "$sha" > vendor/ggen-marketplace/.pin
echo "vendored ash-extension-pack @ $sha"
