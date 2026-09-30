<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

## Summary

<!-- What changed and why. Link the issue. -->

## Verification ladder

Paste real output tails; leave a box unchecked if the step was not run.

- [ ] `mix format --check-formatted`
- [ ] `mix compile --warnings-as-errors`
- [ ] `mix credo --strict`
- [ ] `mix sobelow --skip`
- [ ] `mix dialyzer`
- [ ] `mix test`
- [ ] `mix test --include wasm --include slow --cover` (coverage threshold met)
- [ ] `mix ash_graphlaw.verify`
- [ ] `mix ash_graphlaw.mutate --require-killed` (if behaviour changed)
- [ ] `mix docs` (no warnings)

## Checklist

- [ ] No projection hand-edits: generated files changed only via `ontology.ttl`, `queries/`,
      `templates/`, `ggen.toml` or `scripts/`, then `scripts/ggen_sync.sh`.
- [ ] Any handwritten residue is recorded as `UNSUPPORTED(generator-capability)`.
- [ ] Public API is additive only (no renamed or removed function, DSL option, refusal code or
      task).
- [ ] New tests use real collaborators; no mocks, stubs or patches.
- [ ] `CHANGELOG.md` updated under `[Unreleased]`.
- [ ] No credentials, keys or tokens in the diff.
- [ ] Engine pin (`priv/graphlaw/MANIFEST.json`) unchanged, or changed together with its SHA-256.
