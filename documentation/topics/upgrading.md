<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# upgrading

Moving to `26.9.29` and, separately, bumping the engine pin.

## To 26.9.29

Nothing existing changes shape. `call/2`, `capabilities/1`, `sniff/3`, `law/3`, `hooks/3`, the
`admission` entity and its steps, `Change.Admit`, `Validation.Admissible`, `Preparation.Admit`,
`Law`, `Projection`, `Host`, `Pool`, `EngineLoad` and `WasmConfig` keep their behavior. Additions:

| Addition | Effect on existing code |
|---|---|
| typed capability modules, API, registry, result structs | none until you call them |
| root delegates `parse/2 ... policy/2` and bang forms | new names on `AshGraphLaw` |
| `capability` DSL entity | none unless you declare one |
| refusal codes 36 to 40 | exhaustive case on Refusal.code needs new clauses |
| `Refusal.raw` | new struct field, nil for client-side refusals |
| telemetry `[:ash_graphlaw, :capability, ...]` | new events |
| optional `:reactor` dependency | none unless you add it |

Declaring one `capability` changes behavior for that resource: undeclared ops in lifecycle modules
are then refused with `:capability_not_declared`. A resource that declares none is unchanged.

## Steps

```bash
mix deps.update ash_graphlaw
mix ash_graphlaw.vendor
mix ash_graphlaw.verify
mix ash_graphlaw.parity --evidence-dir tmp/evidence
```

## Bumping the engine pin

The library pins GraphLaw `v26.10.28`, and the registry the library generates from is the same
release; the bump is coordinated. Update `glx:graphLawVersion`, `glx:engineReleaseTag`,
`glx:wasmSha256` and `glx:wasmUrl` in `ontology.ttl` (sha256 from the published release asset,
never from a local build), then re-vendor the registry with `scripts/vendor_registry.sh` and
`scripts/import_registry.sh` (rewrites the `blake3:<registry_blake3>` GENERATED-REGISTRY marker and
the `glx:registryBlake3` literal), then `scripts/ggen_sync.sh` (regenerates `MANIFEST.json` and
`@graphlaw_release`). Then run `mix ash_graphlaw.parity` again; a drift is reported, never masked.

## From pre-release trees

Remove any hand copy of `lib/ash_graphlaw/capability/*` op modules: they are generated. Run
`scripts/vendor_registry.sh`, `scripts/import_registry.sh`, `scripts/ggen_sync.sh`.

## See Also

- [Release a version](../how_to/release_a_version.md)
- [Changelog](../../CHANGELOG.md)
- [Troubleshooting](troubleshooting.md)
