#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
#
# UNSUPPORTED(generator-capability): ash-extension-pack ships reference specs (audit_trail,
# ash_r2rml, notification_extension) inside its own ontology.ttl, and ggen [packs] has no
# consumer-side scoping, so `ggen sync run` also projects those specs and the pack's own
# scripts/README.md. This wrapper runs the real sync, then deletes exactly the projections that
# belong to a foreign aex:packageName (names read from the vendored pack ontology, never
# hard-coded). The pack templates emit unformatted Elixir, so `mix format` then normalizes the
# tree (formatting is deterministic, so two runs converge on identical bytes). Nothing else is
# edited. Exit codes: 0 ok, 2 vendor missing, 3 pin mismatch, 4 sync failed, 5 format failed.
set -euo pipefail
cd "$(dirname "$0")/.."

pack_dir="vendor/ggen-marketplace/packs/ash-extension-pack"
own="ash_graphlaw"
pin_file="vendor/ggen-marketplace/.pin"

[ -d "$pack_dir" ] || { echo "REFUSED(vendor:missing $pack_dir) run scripts/vendor_marketplace.sh" >&2; exit 2; }

want=$(sed -n 's/.*glx:marketplaceSha "\([0-9a-f]\{40\}\)".*/\1/p' ontology.ttl | head -n1)
have=$(cat "$pin_file" 2>/dev/null || true)
if [ -z "$want" ] || [ "$want" != "$have" ]; then
  echo "REFUSED(pin:mismatch ontology=$want vendored=$have)" >&2
  exit 3
fi

# The pack templates carry no `force:`, and `mix format` (below) legitimately changes their
# bytes, so ggen would refuse the next sync as a silent clobber (FM-WRITE-005). The previous
# projections of this package are therefore removed first; they are outputs, never sources. The
# paths are the pack templates' own `to:` lines with {{ package_name }} bound to this package.
sed -n 's/^to: *"\(.*\)" *$/\1/p' "$pack_dir"/templates/*.tmpl | sort -u | while IFS= read -r to; do
  rm -f "$(printf '%s' "$to" | sed "s/{{ *package_name *}}/$own/g")"
done

log=$(mktemp)
ggen sync run >"$log" 2>&1 || { cat "$log" >&2; rm -f "$log"; echo "REFUSED(sync:failed)" >&2; exit 4; }
rm -f "$log"

foreign=$(sed -n 's/^[[:space:]]*aex:packageName "\([a-z0-9_]*\)".*/\1/p' "$pack_dir/ontology.ttl" | sort -u | grep -vx "$own" || true)
for pkg in $foreign; do
  rm -rf "lib/$pkg" "lib/mix/tasks/$pkg.install.ex" "test/${pkg}_composition_test.exs"
done
# The pack's own scripts index documents the pack repository, not this package.
rm -f scripts/README.md
mix format || { echo "REFUSED(format:failed)" >&2; exit 5; }
echo "ggen sync ok; pruned foreign packages: $(echo $foreign | tr '\n' ' ')"
