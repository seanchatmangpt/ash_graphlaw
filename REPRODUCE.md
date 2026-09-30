<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# REPRODUCE

Rebuild `26.9.29` from its pins and compare. Each step names its input and the check that can fail.
Running these is a separate act from reading them: until a step is run and its output kept, its
result here is UNKNOWN.

## Pins

| Input | Where | Value |
|---|---|---|
| Library version | `mix.exs`, `glx:packageVersion` | `26.9.29` |
| Engine release | `glx:engineReleaseTag`, `priv/graphlaw/MANIFEST.json` | `v26.9.28`, sha256 `30f6bc6eca9d125fe805f4c2643818ebb0a1471edec75ed0ed989c734397c645` |
| Capability registry | `glx:registrySha256`, `priv/graphlaw/capability-registry.json` | `registry_sha256` of the vendored file |
| Marketplace | `glx:marketplaceSha`, `vendor/ggen-marketplace/.pin` | commit that carries both packs |
| Generator | `glx:ggenSha` | ggen commit the projections were produced with |

## Steps

```bash
git rev-parse HEAD                                  # record the exact subject
mix deps.get
scripts/vendor_registry.sh --check                  # vendored registry equals ../graphlaw/registry
scripts/import_registry.sh --check                  # ontology.ttl carries that registry
scripts/vendor_marketplace.sh                       # packs at glx:marketplaceSha via git archive
scripts/ggen_sync.sh --check                        # two syncs, byte-identical projections
scripts/ggen_sync.sh --check-ledger
scripts/ggen_sync.sh --check-versions
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix ash_graphlaw.vendor                             # fetches the pinned engine; needs your consent
mix ash_graphlaw.verify
mix test --include wasm
mix ash_graphlaw.parity --evidence-dir tmp/evidence
MIX_ENV=test mix ash_graphlaw.mutate --require-killed
mix hex.build
```

## Compare

- `sha256sum priv/graphlaw/graphlaw.wasm` equals the pin above.
- `tmp/evidence/parity_report.json` lists checks `P1` to `P9` and `R1`. Against the `v26.9.28`
  engine a drift is a valid outcome; it is reported, not masked.
- `scripts/ggen_sync.sh --check` prints one `sha256  path` line per projection; two runs must match.

## What a reproduction proves

That this tree, these pins and this toolchain produced these outputs. It is `PARTIAL_ALIVE` for
the checks that passed. `ALIVE` needs an exact-SHA receipt for the published commit
(`<<RECEIPT:claim-4>>`).

## See Also

- [Release a version](documentation/how_to/release_a_version.md)
- [Claims and evidence](documentation/reference/claims_and_evidence.md)
- [Contributing](CONTRIBUTING.md)
