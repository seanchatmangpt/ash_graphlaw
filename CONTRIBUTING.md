<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Contributing

## Workflow

Development happens on `main` only. There are no long-lived branches, worktrees or copies of the
repository. Never rebase and never force push; integrate with ordinary merges or forward commits, and
fix forward with new commits (use `git revert` for undoing).

Write commit messages to a file and commit with `git commit -F <file>`.

## Edit sources, not generated outputs

Generated files are projections of `ontology.ttl`, `queries/`, `templates/` and `ggen.toml`. Do not
edit them by hand: change the source and run `scripts/ggen_sync.sh` (`scripts/vendor_marketplace.sh` first when `vendor/` is absent).

Generated: `mix.exs`, `.formatter.exs`, `.gitignore`, `README.md`, `lib/ash_graphlaw.ex`,
`lib/ash_graphlaw/{abi,receipt,admitted,standing,refusal,resource,persist,verify,info}.ex`,
`lib/mix/tasks/ash_graphlaw.install.ex`, `documentation/reference/typed_refusals.md`,
the typed capability surface (`lib/ash_graphlaw/capability.ex`, `capability/{registry,api}.ex`,
one module per op under `capability/` and `result/`, `documentation/reference/capabilities.md` and
`capabilities/*.md`, `test/generated/capability_surface_test.exs`),
`documentation/dsls/DSL-AshGraphLaw.Resource.md` (via `mix spark.cheat_sheets`) and
`priv/graphlaw/MANIFEST.json`.

Everything else is hand-written residue and carries an `UNSUPPORTED(generator-capability)` note
explaining why no pack emits it. Prefer extending the ontology or a template over adding residue.

## Verification ladder

Run the cheapest checks first and stop at the first failure:

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix ash_graphlaw.vendor          # needed for tests tagged :wasm
mix test
mix ash_graphlaw.parity          # capability parity court; never skips
mix ash_graphlaw.mutate --require-killed
mix hex.build
```

Report real command output in pull requests. A failure that predates your change is reported as
pre-existing, not silently ignored.

## Registry changes

When the GraphLaw capability registry changes, run `scripts/vendor_registry.sh`,
`scripts/import_registry.sh`, `scripts/vendor_marketplace.sh` (when the marketplace sha moves) and
`scripts/ggen_sync.sh`, then `scripts/ggen_sync.sh --check`. Never edit the `GENERATED-REGISTRY`
block of `ontology.ttl` or a generated capability module by hand.

## Documentation

Docs follow Diataxis (`documentation/{tutorials,how_to,reference,topics}`). Every `.md` starts with
the SPDX comment. State standing with the vocabulary; do not write `ALIVE` without an exact-SHA
receipt; leave `<<RECEIPT:claim-N>>` tokens in place. Describe only what you re-read in source; a
claim about code you did not run is `UNKNOWN`.

## Testing

Tests follow the Chicago (classicist) style: real collaborators, assertions on final state, and no
mocks (no Mox, Mimic, meck or patching). Use the real pinned wasm through the `:wasm` tag. Write a
positive control before each negative assertion so a refusal test cannot pass vacuously.

## SPDX headers

Every `.ex`, `.exs`, `.yml`, `.toml` and `.tmpl` file starts with:

```text
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
```

Markdown files use the same fields inside an HTML comment. Files that cannot carry a header are
covered by `REUSE.toml`. Check compliance with `reuse lint`.

## Reporting security issues

Do not use public issues; follow [SECURITY.md](SECURITY.md).
