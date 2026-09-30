#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
#
# UNSUPPORTED(generator-capability): hand-written smoke script; no pack emits installer smoke tests.
#
# Installer smoke: run the REAL `mix ash_graphlaw.install --target My.Res` task in a scratch Igniter
# project OUTSIDE this repository and assert on the resulting files.
#
#   scripts/installer_smoke.sh [--scratch DIR] [--keep] [--compile]
#
# Checks (each prints PASS/FAIL with the evidence):
#   1. --target My.Res adds AshGraphLaw.Resource to the resource's `extensions:`
#   2. .formatter.exs gains `:ash_graphlaw` in import_deps and AshGraphLaw.Formatter in plugins
#   3. mix.exs gains the wasmex dependency
#   4. a second run leaves every file byte-identical (idempotent)
#   5. a run WITHOUT --target prints the manual notice and leaves the resource byte-identical
#   6. (--compile) the patched scratch project compiles
#
# Exit status: 0 when every executed check passes, 1 when any check fails, 2 on a setup error.
# A failing check 1 with a SyntaxError is the known installer defect: the fix belongs in
# ontology.ttl (aex installer target-mode individuals), never in the generated projection.

set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=""
keep=0
compile=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scratch) scratch="${2:?--scratch needs a directory}"; shift 2 ;;
    --keep) keep=1; shift ;;
    --compile) compile=1; shift ;;
    -h | --help) sed -n '5,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$scratch" ]; then
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/ash_graphlaw_installer_smoke.XXXXXX")" || exit 2
else
  mkdir -p "$scratch" || exit 2
  scratch="$(cd "$scratch" && pwd)"
fi

# The scratch project must never live inside the repository.
case "$scratch/" in
  "$repo"/*) echo "refusing: scratch dir $scratch is inside the repository $repo" >&2; exit 2 ;;
esac

cleanup() {
  if [ "$keep" -eq 0 ]; then rm -rf "$scratch"; else echo "scratch kept at $scratch"; fi
}
trap cleanup EXIT

project="$scratch/smoke_app"
failures=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

check() { # check <name> <command...>
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

digest_tree() { # stable digest of the project sources (not deps/_build)
  (cd "$project" && find lib mix.exs .formatter.exs -type f -print0 2>/dev/null | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
}

echo "repo:    $repo"
echo "scratch: $project"

(cd "$scratch" && mix new smoke_app --sup >/dev/null 2>"$scratch/mix_new.err") || {
  echo "setup error: mix new failed" >&2
  cat "$scratch/mix_new.err" >&2
  exit 2
}

mkdir -p "$project/lib/my"

cat >"$project/mix.exs" <<EOF
defmodule SmokeApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :smoke_app,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: false,
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:ash, ">= 3.0.0"},
      {:igniter, ">= 0.6.29 and < 1.0.0-0"},
      {:ash_graphlaw, path: "$repo"}
    ]
  end
end
EOF

mkdir -p "$project/config"
cat >"$project/config/config.exs" <<'EOF'
import Config

config :ash, default_string_length_count: :codepoints
config :ash_graphlaw, start_pool: false
EOF

cat >"$project/.formatter.exs" <<'EOF'
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
EOF

cat >"$project/lib/my/domain.ex" <<'EOF'
defmodule My.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource My.Res
  end
end
EOF

cat >"$project/lib/my/res.ex" <<'EOF'
defmodule My.Res do
  use Ash.Resource,
    domain: My.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key(:id)
  end
end
EOF

cd "$project" || exit 2

echo "== mix deps.get"
if ! mix deps.get >"$scratch/deps.log" 2>&1; then
  echo "setup error: mix deps.get failed" >&2
  tail -20 "$scratch/deps.log" >&2
  exit 2
fi

res="$project/lib/my/res.ex"
cp "$res" "$scratch/res.before"

echo "== mix ash_graphlaw.install --target My.Res --yes"
mix ash_graphlaw.install --target My.Res --yes >"$scratch/install1.log" 2>&1
install1=$?
echo "exit status: $install1"

if grep -q "SyntaxError" "$scratch/install1.log"; then
  echo "evidence: $(grep -m1 -A1 SyntaxError "$scratch/install1.log" | tr '\n' ' ')"
fi

check "1 extension added: extensions: [AshGraphLaw.Resource]" grep -q "extensions: \[AshGraphLaw.Resource\]" "$res"
check "2a formatter import_deps has :ash_graphlaw" grep -q ":ash_graphlaw" "$project/.formatter.exs"
check "2b formatter plugin AshGraphLaw.Formatter" grep -q "AshGraphLaw.Formatter" "$project/.formatter.exs"
check "3 mix.exs has the wasmex dependency" grep -Eq '\{:wasmex, *"~> 0\.15' "$project/mix.exs"

first_digest="$(digest_tree)"

echo "== second run (idempotence)"
mix ash_graphlaw.install --target My.Res --yes >"$scratch/install2.log" 2>&1
second_digest="$(digest_tree)"
if [ "$first_digest" = "$second_digest" ]; then pass "4 second run leaves every source byte-identical"; else fail "4 second run changed sources"; fi
check "4b extension still declared exactly once" test "$(grep -o 'AshGraphLaw.Resource' "$res" | wc -l | tr -d ' ')" = "1"

echo "== missing --target (manual-notice path) on a pristine resource"
cp "$scratch/res.before" "$res"
before_notice="$(digest_tree)"
mix ash_graphlaw.install --yes >"$scratch/install3.log" 2>&1
check "5a manual notice names --target" grep -q -- "--target MyApp.SomeResource" "$scratch/install3.log"
check "5b manual notice names the extension" grep -q "extensions: \[AshGraphLaw.Resource\]" "$scratch/install3.log"
check "5c resource left byte-identical" cmp -s "$scratch/res.before" "$res"
: "$before_notice"

if [ "$compile" -eq 1 ]; then
  echo "== compile the patched project"
  cp "$scratch/res.before" "$res"
  mix ash_graphlaw.install --target My.Res --yes >/dev/null 2>&1
  check "6 patched scratch project compiles" mix compile
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "installer smoke: all checks passed"
  exit 0
fi
echo "installer smoke: $failures check(s) failed"
exit 1
