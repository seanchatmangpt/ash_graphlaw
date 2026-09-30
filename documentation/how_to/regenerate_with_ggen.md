<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Regenerate with ggen

Change a generated file by changing its source, then run the sync.

## Sources and projections

| Source | Projects |
|---|---|
| `ontology.ttl` (including the `GENERATED-REGISTRY` block) | refusal table, DSL structs, manifest, capability modules |
| `queries/*.rq`, `templates/*.tmpl`, `ggen.toml` | local templates: root API, refusal, `mix.exs`, README |
| `graphlaw-ash-capability-pack` (vendored under `vendor/ggen-marketplace/packs/`) | `AshGraphLaw.Capability.*`, `AshGraphLaw.Result.*`, `capabilities.md` reference |

Do not edit a projection. `scripts/ggen_sync.sh --list-projections` prints every generated path.

## Steps

```bash
scripts/vendor_registry.sh          # copy ../graphlaw/registry/* to priv/graphlaw/, verify digest
scripts/import_registry.sh          # splice the registry TTL into ontology.ttl
scripts/vendor_marketplace.sh       # materialize the packs at glx:marketplaceSha (git archive)
scripts/ggen_sync.sh                # ggen sync run, prune foreign specs, mix format
scripts/ggen_sync.sh --check        # sync twice; refuse on any byte difference
scripts/ggen_sync.sh --check-ledger # every glx:residuePath appears in HANDWRITTEN.md
scripts/ggen_sync.sh --check-versions
```

`vendor_registry.sh --check` and `import_registry.sh --check` write nothing and exit 1 on a
difference.

## Exit codes of `ggen_sync.sh`

| Exit | Meaning |
|---|---|
| 0 | ok |
| 2 | `vendor/` missing |
| 3 | pin mismatch between `ontology.ttl` and `vendor/ggen-marketplace/.pin` |
| 4 | `ggen sync run` failed |
| 5 | `mix format` failed |
| 6 | non-deterministic projections (`--check`) |
| 7 | ledger gap (`--check-ledger`) |
| 8 | version drift (`--check-versions`) |
| 64 | usage |

## When the generator cannot emit something

Write the file by hand, start it with `# UNSUPPORTED(generator-capability): <reason>`, add a
`glx:UnsupportedResidue` row to `ontology.ttl` and a row to `HANDWRITTEN.md`. Prefer extending the
ontology or a template.

## See Also

- [Generation and residue](../topics/generation_and_residue.md)
- [Capability registry and parity](../topics/capability_registry_and_parity.md)
- [Usage rule: ontology-first](../../usage-rules/ontology-first.md)
