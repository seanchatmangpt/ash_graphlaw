<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# generation_and_residue

The library is ontology-first. Sources are edited; outputs are projections.

## Sources

| Source | Role |
|---|---|
| ontology.ttl | Project facts, pins, refusal-code table, standing table, pack spec rows |
| `queries/*.rq` | SPARQL SELECT queries with `ORDER BY` (project, standing, refusal codes, WASI imports). Each is copied verbatim into the frontmatter of the template that uses it; `test/unit/template_query_sync_test.exs` refuses drift |
| `templates/*.tmpl` | Local consumer templates; each carries its own `to:` target and inline `sparql:` (ggen frontmatter schema) |
| ggen.toml | Frontmatter-schema manifest: ontology, `[packs]`, `[templates]`, `[law] gates` |
| `gates/*.rq` | Pre-generation contract checks, run by ggen as `[law] gates` |
| ggen-marketplace `ash-extension-pack` | Spark extension, persister, verifier, info, installer |

## What ggen emits

- From the pack: `resource.ex`, `persist.ex`, `verify.ex`, `info.ex`, the install task and a
  composition test.
- From local templates: `mix.exs`, `.formatter.exs`, `.gitignore`, `README.md`, the root API
  module, `ABI`, `Receipt`, `Admitted`, `Standing`, `Refusal`, `priv/graphlaw/MANIFEST.json`,
  `test/test_helper.exs` and `documentation/reference/typed_refusals.md`.
- From a tool, not ggen: `documentation/dsls/DSL-AshGraphLaw.Resource.md` via `mix spark.cheat_sheets`.

## What is hand-written, and why

No listed pack emits these, so they are irreducible residue, each labeled
`UNSUPPORTED(generator-capability)`:

- the WASM host, pool, engine loader and wasm config (no pack emits a Wasmex host);
- Ash `Change`, `Validation` and `Preparation` modules and the Splode error (no pack emits them);
- the projection behaviour and default projection, the law behaviour, evidence;
- the mutation engine and the vendor, verify and mutate mix tasks;
- `AshGraphLaw.Authority`, the one authority boundary shared by the change and the validation;
- `scripts/ggen_sync.sh` and `scripts/vendor_marketplace.sh` (see below);
- tests, prose documentation, usage rules, workflows and configuration.

### Why the sync goes through `scripts/ggen_sync.sh`

`UNSUPPORTED(generator-capability)`, measured against ggen 26.9.28 and `ash-extension-pack`
`caa4fe61`:

- A `ggen.toml` is either the declarative-rules schema (`[[generation.rules]]`) or the frontmatter
  schema (`[packs]`, `[templates]`); mixing them is refused (`FM-CONFIG-101`). Pack templates only
  render under the frontmatter schema, so the local templates carry frontmatter too.
- The pack's own `ontology.ttl` carries three reference specs (`audit_trail`, `ash_r2rml`,
  `notification_extension`). ggen has no consumer-side scoping, so a sync also projects those, plus
  the pack's `scripts/README.md`. The script deletes exactly the projections of foreign
  `aex:packageName` values, read from the vendored pack ontology.
- The pack templates emit unformatted Elixir and carry no `force:`. The script removes this
  package's previous pack projections before syncing (ggen would otherwise refuse the formatted file
  as a silent clobber) and runs `mix format` after.
- The pack's installer template inserts `extensions: [...]` as a statement, which does not parse, so
  the installer's `--target` mode raises; the tests pin that behavior rather than hide it.

The `ash-extension-core` and `ash-extension-starter` packs are superseded by
`ash-extension-pack`. The `canonical-ash-projection-generator` and
`ash-runtime-integration-contract-pack` emit semantic maps and runtime scaffolds, not a Spark
extension or a Wasmex host.

## Regeneration rule

Edit sources, never outputs. To change a generated file:

1. Change `ontology.ttl`, a query (and the same text in its template), a template or `ggen.toml`.
2. Run `scripts/vendor_marketplace.sh` if `vendor/` is absent, then `scripts/ggen_sync.sh`.
3. Confirm the output set is byte-identical across two consecutive runs (the `manufacture`
   workflow does exactly this).

A hand edit to a generated file is overwritten on the next sync and is a defect, not a fix. Pin literals (`ggenSha`, `marketplaceSha`, `wasmSha256`) live in the ontology
and are the only values the integrator edits by hand.

## See Also

- [Support matrix](../reference/support_matrix.md)
- [Architecture](architecture.md)
- [Typed refusals](../reference/typed_refusals.md) (generated)
