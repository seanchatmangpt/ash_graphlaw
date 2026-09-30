#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
#
# Materializes vendor/ggen-marketplace/packs/{ash-extension-pack,graphlaw-ash-capability-pack}
# from the exact marketplace sha pinned in ontology.ttl (glx:marketplaceSha) with `git archive`;
# no clone, no worktree. The source repository defaults to ~/ggen-marketplace (override with
# GGEN_MARKETPLACE_REPO). The sha is recorded in vendor/ggen-marketplace/.pin and re-checked by
# scripts/ggen_sync.sh. A pack absent at the pinned sha refuses (exit 3); nothing is skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

packs=(ash-extension-pack graphlaw-ash-capability-pack)

repo="${GGEN_MARKETPLACE_REPO:-$HOME/ggen-marketplace}"
sha=$(sed -n 's/.*glx:marketplaceSha "\([0-9a-f]\{40\}\)".*/\1/p' ontology.ttl | head -n1)
[ -n "$sha" ] || { echo "REFUSED(pin:absent glx:marketplaceSha)" >&2; exit 2; }

rm -rf vendor/ggen-marketplace
mkdir -p vendor/ggen-marketplace
for pack in "${packs[@]}"; do
  git -C "$repo" archive "$sha" "packs/$pack" | tar -x -C vendor/ggen-marketplace || {
    echo "REFUSED(pack:absent packs/$pack at $sha in $repo)" >&2
    exit 3
  }
  [ -d "vendor/ggen-marketplace/packs/$pack" ] || { echo "REFUSED(pack:empty packs/$pack)" >&2; exit 3; }
done
printf '%s\n' "$sha" > vendor/ggen-marketplace/.pin
echo "vendored ${packs[*]} @ $sha"
