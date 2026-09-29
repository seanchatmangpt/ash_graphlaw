<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Ggen

ggen is the manufacturer, not the runtime. Ontology is source; generated files are
projections.

## Sources (edit these)

`ontology.ttl`, `queries/*.rq`, `gates/*.rq`, `templates/*.tmpl`, `ggen.toml`.

## Generated (never hand-edit)

- From `ash-extension-pack`: `lib/ash_graphlaw/{resource,persist,verify,info}.ex`,
  `lib/mix/tasks/ash_graphlaw.install.ex`, `test/ash_graphlaw_composition_test.exs`,
  `LICENSE`.
- From local templates: `mix.exs`, `.formatter.exs`, `.gitignore`, `README.md`,
  `lib/ash_graphlaw.ex`, `lib/ash_graphlaw/{abi,receipt,admitted,standing,refusal}.ex`,
  `documentation/reference/typed_refusals.md`, `priv/graphlaw/MANIFEST.json`,
  `test/test_helper.exs`.
- From `mix spark.cheat_sheets`: `documentation/dsls/DSL-AshGraphLaw.Resource.md`.

## Workflow

1. Edit the source (ontology row, query, template, `ggen.toml`).
2. `scripts/vendor_marketplace.sh` once (materializes the pinned pack with `git archive`), then
   `scripts/ggen_sync.sh` (runs `ggen sync run`, prunes the pack's reference-spec projections,
   formats). Preview with `ggen sync run --dry-run --format json`.
3. Re-run the ladder. If output is wrong, fix the source and regenerate.

## Rules

- Do not run `ggen sync` outside the integration step of a work order.
- Do not hand-fix a generated file; the next sync overwrites it.
- Do give every `SELECT` an `ORDER BY` (ggen E0013).
- Do keep pins (`ggenSha`, `marketplaceSha`, `wasmSha256`) as literals in `ontology.ttl`
  only.
- `vendor/` is gitignored scratch, populated from `git archive` of the pinned marketplace
  SHA. Never clone or add worktrees.
- Hand-written residue is labeled `UNSUPPORTED(generator-capability)`: Host, Pool,
  EngineLoad, WasmConfig, Application, Admissions, Contract, Formatter, CheatSheet, Law,
  Projection, Evidence, Error, Change/Validation/Preparation, Mutation, and the
  `vendor|verify|mutate` Mix tasks.
- Whether `[packs]` auto-renders pack templates is UNKNOWN until a real sync runs.

## See Also

[setup.md](setup.md) - [../AGENTS.md](../AGENTS.md) - [../usage-rules.md](../usage-rules.md)
