<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# capability_registry_and_parity

How the typed surface is derived from the engine, and how drift is detected.

## The registry

GraphLaw owns the capability registry: a Rust static table (`src/registry.rs`) emitted as
`registry/capability-registry.json`, `.ttl`, `op-examples.json` and their schemas. Schema id
`graphlaw.capability-registry/1`. It lists the 14 ABI ops in order, each with request fields,
response variants, refusal kinds and codes, plus dialects, regimes, lease vocabularies, law steps and
limits. Three digests travel with it: `registry_blake3` (the whole document without its own
digest key), `surface_blake3` (abi version, ops, dialects) and `receipt_surface_blake3` (the
receipt-minting surface; a registry-document field, not reported in the live `capabilities`
response). The digest rule is key-following: blake3 via `b3sum` is the default; a registry of the
`registry_sha256`/`surface_sha256` era is verified with SHA-256 instead. Either way the bytes are
canonical JSON (sorted keys, compact, integers only), so the engine and the library compute the
same digest.

## From registry to typed modules

```text
graphlaw registry (Rust table)
   -> registry/capability-registry.{json,ttl}, op-examples.json
   -> scripts/vendor_registry.sh   -> priv/graphlaw/
   -> scripts/import_registry.sh   -> ontology.ttl (GENERATED-REGISTRY block)
   -> graphlaw-ash-capability-pack -> scripts/ggen_sync.sh
   -> AshGraphLaw.Capability.*, Result.*, Registry, API, reference pages
```

Generated files are projections; the hand-written parts (`CanonicalJSON`, `Coerce`, `Decode`,
`Telemetry`, `Parity`, lifecycle modules) are ledgered in `HANDWRITTEN.md` as
`UNSUPPORTED(generator-capability)`.

## Expose, do not reimplement

The library builds a request, sends it to the engine, and decodes the answer. It never evaluates
RDF, SPARQL, SHACL, ShEx, N3, Datalog, entailment or planning itself. Semantic success is
`PARTIAL_ALIVE` at most until exact consequence is observed.

## The parity court

`mix ash_graphlaw.parity` asks the live engine for `capabilities` and compares it with the
generated registry and the typed modules:

| Check | Claim |
|---|---|
| P1 | live ops equal `Registry.names/0`, in order |
| P2 | live dialect lists equal the registry |
| P3 | surface and registry digests match (declared digest key: blake3, or legacy sha256) |
| P4, P5 | typed modules and API cover exactly the registry ops |
| P6 | the admission DSL step enum equals the registry law steps |
| P7 | every registry refusal code maps to a known atom |
| P8 | no supported op needs `call/2` |
| P9 | every op example reproduces through the typed API on the live engine |
| R1 | the vendored registry JSON digest equals `Registry.digest/0` |

A failing check is a failing court: `[capability_parity_drift] <ids>`. The court never skips.

## Status of this release

The engine pin is `v26.10.28` (asset sha256 `34fd4ada…`), and the vendored registry is the same
release (`26.10.28`), declaring blake3 digests. The engine reports `registry_blake3`/
`surface_blake3`, so `P3`'s registry field matches live. Whether every check passes is what a court
run shows; a drift is reported, never masked. A pass is `PARTIAL_ALIVE`.

## See Also

- [Run the parity court](../how_to/run_the_parity_court.md)
- [Use typed capabilities](../how_to/use_typed_capabilities.md)
- [Generation and residue](generation_and_residue.md)
- [Capabilities reference](../reference/capabilities.md) (generated)
