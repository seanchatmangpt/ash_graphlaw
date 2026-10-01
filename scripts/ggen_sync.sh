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
# edited.
#
# Both packs (ash-extension-pack, graphlaw-ash-capability-pack) are synced by the one `ggen sync
# run`; the pruning of foreign reference specs is read from every vendored pack ontology, and the
# previous projections of every pack are removed before the sync (pack templates carry no force).
#
# Usage: scripts/ggen_sync.sh [--check | --check-ledger | --check-versions | --list-projections | --help]
#   (none)            run the sync once (default behavior).
#   --check           determinism self-check: sync twice and compare the sha256 manifest of
#                     every projection in PROJECTIONS; prints the manifest, refuses on any
#                     difference.
#   --check-ledger    every glx:residuePath in ontology.ttl has an entry in HANDWRITTEN.md
#                     (no sync and no vendored pack needed).
#   --check-versions  every glx:VersionBinding in ontology.ttl is carried by its file on disk
#                     (no sync and no vendored pack needed).
#   --list-projections  print every path in PROJECTIONS, one per line (the single source the
#                     manufacture workflow reads; documentation/dsls/** is hashed separately).
#
# Exit codes: 0 ok, 2 vendor missing, 3 pin mismatch, 4 sync failed, 5 format failed,
# 6 non-deterministic projections (--check), 7 ledger gap (--check-ledger), 8 version drift
# (--check-versions), 64 usage.
set -euo pipefail
cd "$(dirname "$0")/.."

packs=(ash-extension-pack graphlaw-ash-capability-pack)
pack_root="vendor/ggen-marketplace/packs"
own="ash_graphlaw"
pin_file="vendor/ggen-marketplace/.pin"

# Capability op names in registry order (the 14 ABI ops of graphlaw.capability-registry/1). The
# parity court (mix ash_graphlaw.parity, P4/P5) proves this list against the live registry; the
# gates never hardcode the count. The law op decodes to AshGraphLaw.Admitted (OpBinding
# bindingResultModule), so it has a capability module and a doc but no Result module.
CAPABILITY_OPS=(
  capabilities sniff parse convert canonical sparql shacl shex n3 entail datalog hooks law policy
)
RESULT_OPS=(
  capabilities sniff parse convert canonical sparql shacl shex n3 entail datalog hooks policy
)

# Every projection this wrapper is answerable for (seam S1). Hashed by --check.
PROJECTIONS=(
  mix.exs README.md .formatter.exs .gitignore test/test_helper.exs
  priv/graphlaw/MANIFEST.json documentation/reference/typed_refusals.md LICENSE ggen.lock
  CITATION.cff engineering-standards.json
  lib/ash_graphlaw.ex
  lib/ash_graphlaw/abi.ex lib/ash_graphlaw/receipt.ex lib/ash_graphlaw/admitted.ex
  lib/ash_graphlaw/standing.ex lib/ash_graphlaw/refusal.ex lib/ash_graphlaw/resource.ex
  lib/ash_graphlaw/persist.ex lib/ash_graphlaw/verify.ex lib/ash_graphlaw/info.ex
  lib/mix/tasks/ash_graphlaw.install.ex test/ash_graphlaw_composition_test.exs
  # graphlaw-ash-capability-pack projections
  lib/ash_graphlaw/capability.ex lib/ash_graphlaw/capability/registry.ex
  lib/ash_graphlaw/capability/api.ex lib/ash_graphlaw/result/term.ex
  documentation/reference/capabilities.md test/generated/capability_surface_test.exs
  lib/ash_graphlaw/capability/limits.ex lib/ash_graphlaw/model/enums.ex documentation/reference/COVERAGE.md
)
for op in "${CAPABILITY_OPS[@]}"; do
  PROJECTIONS+=("lib/ash_graphlaw/capability/$op.ex" "documentation/reference/capabilities/$op.md")
done
for op in "${RESULT_OPS[@]}"; do
  PROJECTIONS+=("lib/ash_graphlaw/result/$op.ex")
done

usage() {
  echo "usage: scripts/ggen_sync.sh [--check | --check-ledger | --check-versions | --list-projections | --help]" >&2
}

# "<sha256>  <path>" per projection, "MISSING  <path>" when absent, sorted by path.
manifest() {
  local f
  for f in "${PROJECTIONS[@]}"; do
    if [ -f "$f" ]; then shasum -a 256 "$f"; else printf 'MISSING  %s\n' "$f"; fi
  done | LC_ALL=C sort -k2
  if [ -d documentation/dsls ]; then
    find documentation/dsls -type f | LC_ALL=C sort | while IFS= read -r f; do shasum -a 256 "$f"; done
  fi
}

# Ontology rows, one statement per line in the shapes ontology.ttl uses.
residue_paths() { sed -n 's/^.*glx:residuePath "\([^"]*\)".*$/\1/p' ontology.ttl; }
binding_rows() {
  sed -n 's/^glx:[A-Za-z0-9]* a glx:VersionBinding ; glx:bindingPath "\([^"]*\)" ; glx:bindingKind "\([^"]*\)" ; glx:bindingValue "\([^"]*\)" \.$/\1|\2|\3/p' ontology.ttl
}

check_ledger() {
  local ledger=HANDWRITTEN.md n=0 gaps=0 path
  [ -f "$ledger" ] || { echo "REFUSED(ledger:absent $ledger)" >&2; return 7; }
  while IFS= read -r path; do
    n=$((n + 1))
    grep -qF -- "$path" "$ledger" || { echo "REFUSED(ledger:gap $path has no $ledger entry)" >&2; gaps=$((gaps + 1)); }
  done < <(residue_paths)
  [ "$n" -gt 0 ] || { echo "REFUSED(ledger:empty no glx:residuePath rows)" >&2; return 7; }
  [ "$gaps" -eq 0 ] || return 7
  echo "ledger ok: $n residue paths, all present in $ledger"
}

check_versions() {
  local path kind val esc pat n=0 bad=0
  while IFS='|' read -r path kind val; do
    n=$((n + 1))
    if [ ! -f "$path" ]; then echo "REFUSED(version:absent $path)" >&2; bad=$((bad + 1)); continue; fi
    esc=$(printf '%s' "$val" | sed 's/\./\\./g')
    case "$path" in
      mix.exs) pat="@version \"$esc\"" ;;
      priv/graphlaw/MANIFEST.json) pat="\"graphlaw_version\": \"$esc\"" ;;
      *) pat="(^|[^0-9.])${esc}([^0-9]|\$)" ;;
    esac
    if grep -Eq -- "$pat" "$path"; then
      echo "ok  $path ($kind $val)"
    else
      echo "REFUSED(version:drift $path does not carry $kind $val)" >&2
      bad=$((bad + 1))
    fi
  done < <(binding_rows)
  [ "$n" -gt 0 ] || { echo "REFUSED(version:empty no glx:VersionBinding rows)" >&2; return 8; }
  [ "$bad" -eq 0 ] || return 8
  echo "versions ok: $n bindings"
}

run_sync() {
  local pack pack_dir
  for pack in "${packs[@]}"; do
    pack_dir="$pack_root/$pack"
    [ -d "$pack_dir" ] || { echo "REFUSED(vendor:missing $pack_dir) run scripts/vendor_marketplace.sh" >&2; exit 2; }
  done

  local want have
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
  local to
  for pack in "${packs[@]}"; do
    for to in $(sed -n 's/^to: *"\(.*\)" *$/\1/p' "$pack_root/$pack"/templates/*.tmpl | sort -u | tr ' ' '\001'); do
      to=$(printf '%s' "$to" | tr '\001' ' ' | sed "s/{{ *package_name *}}/$own/g")
      # for_each templates carry an unbound loop variable in `to:`; their outputs are removed
      # through PROJECTIONS below.
      case "$to" in *"{{"*) continue ;; esac
      rm -f "$to"
    done
  done
  # Every declared projection of this package (both packs) is an output, never a source. The
  # capability set is removed explicitly so for_each outputs are deleted like the first pack's.
  local proj
  for proj in "${PROJECTIONS[@]}"; do
    case "$proj" in
      lib/ash_graphlaw/capability*|lib/ash_graphlaw/result/*|lib/ash_graphlaw/model/*|documentation/reference/COVERAGE.md|documentation/reference/capabilities*|test/generated/*)
        rm -f "$proj" ;;
    esac
  done

  local log foreign pkg
  log=$(mktemp)
  ggen sync run >"$log" 2>&1 || { cat "$log" >&2; rm -f "$log"; echo "REFUSED(sync:failed)" >&2; exit 4; }
  rm -f "$log"

  foreign=$(for pack in "${packs[@]}"; do
    sed -n 's/^[[:space:]]*aex:packageName "\([a-z0-9_]*\)".*/\1/p' "$pack_root/$pack/ontology.ttl" 2>/dev/null || true
  done | sort -u | grep -vx "$own" || true)
  for pkg in $foreign; do
    rm -rf "lib/$pkg" "lib/mix/tasks/$pkg.install.ex" "test/${pkg}_composition_test.exs"
  done
  # The pack's own scripts index documents the pack repository, not this package.
  rm -f scripts/README.md
  # The pack installer inserts `extensions: [...]` as a bare statement (Igniter add_code/3 parses
  # a statement), so `--target` raises SyntaxError. Until the pack template is fixed, the
  # corrected installer in scripts/patches/ replaces the projection, but only while the pack
  # output still carries the defect; once the pack emits Spark.Igniter.add_extension the
  # replacement retires itself. Ledgered in HANDWRITTEN.md.
  local installer=lib/mix/tasks/ash_graphlaw.install.ex
  if [ -f "$installer" ] && grep -q 'Igniter.Code.Common.add_code(zipper, "extensions:' "$installer"; then
    cp scripts/patches/ash_graphlaw.install.ex "$installer"
    echo "installer: applied scripts/patches/ash_graphlaw.install.ex (pack add_extension defect)"
  fi
  mix format || { echo "REFUSED(format:failed)" >&2; exit 5; }
  echo "ggen sync ok; pruned foreign packages: $(echo $foreign | tr '\n' ' ')"
}

case "${1:-}" in
  "") run_sync ;;
  --check)
    run_sync
    first=$(manifest)
    run_sync
    second=$(manifest)
    if [ "$first" = "$second" ]; then
      printf '%s\n' "$second"
      echo "determinism ok: two syncs produced byte-identical projections ($(printf '%s\n' "$second" | wc -l | tr -d ' ') files hashed)"
    else
      echo "REFUSED(determinism:differs)" >&2
      diff <(printf '%s\n' "$first") <(printf '%s\n' "$second") >&2 || true
      exit 6
    fi
    ;;
  --check-ledger) check_ledger ;;
  --check-versions) check_versions ;;
  --list-projections) printf '%s\n' "${PROJECTIONS[@]}" ;;
  -h|--help) usage ;;
  *) echo "REFUSED(usage:unknown-flag $1)" >&2; usage; exit 64 ;;
esac
