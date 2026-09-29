<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses calendar versioning
(`YY.M.N`).

## [Unreleased]

### Changed (authority)

- A ceiling above `:observe` is met only by a SIGNED lease (`%{signed_lease: %{"lease" => ...,
  "attestation" => ...}}`) in the changeset context. A bare atom, `%{ceiling: _}`, an unsigned
  `:lease` or `:unverified_lease` grants `:observe`. New `AshGraphLaw.Authority` is the one boundary
  shared by `Change.Admit` and `Validation.Admissible` (the validation path previously called a
  private function and used different trust material).
- `trusted_keys` and `max_skew_secs` come only from the resource `runtime` section; `now_unix`,
  `lease` and `unverified_lease` from caller context are never forwarded to the engine.
- `AshGraphLaw.Evidence` records the engine `wasm_sha256` and the presented lease identity (`lease`:
  ceiling, lease id, signer key id, lease digest). It raises on unknown options.

### Changed (host and loader)

- `EngineLoad.admit/2` judges a hex pin BEFORE compiling the bytes, and admits imports only from the
  manifest allowlist by module, name and type (`glx:WasiImport` rows).
- `Host` answers the caller before a recycle, retries a failed load with capped backoff, leaves the
  pool's `:members` registration while unavailable, refuses responses over `max_response_bytes`, and
  applies `table_elements`, `instances`, `tables` and `memories` store limits. Fuel now defaults to
  `timeout_ms * fuel_per_ms`. `Pool.request/2` forwards to an unavailable member when none is live.
- Text that is not valid UTF-8 is `:invalid_encoding` (from `AshGraphLaw.ABI`), not `:invalid_json`.
- Engine refusals: `ReceiptRefused` and `UnverifiedLeaseRefused` are mapped; a known engine kind
  without a table code is `:engine_refused`, an unknown one `:engine_unclassified`.
- `Contract.validate/1` is fail-closed on a malformed compiled state and refuses a `law` module that
  is absent or lacks `steps/2`.
- `mix ash_graphlaw.vendor` installs through a temporary file and never deletes an existing
  pin-verified engine on a mismatch.
- The mutation runner compiles only files under `test/` and refuses a file that redefines a module
  loaded from outside `test/`; mutation `AGL-MUT-010` moved to `AshGraphLaw.ABI` and `AGL-MUT-014`
  was added.

### Changed (manufacture)

- `ggen.toml` uses the frontmatter schema: local templates are `templates/*.tmpl` with inline
  `sparql:`, gates run as `[law] gates`, and `ash-extension-pack` is bound through `[packs]`.
  `scripts/vendor_marketplace.sh` and `scripts/ggen_sync.sh` are the entry points.
- Generated: `resource.ex`, `persist.ex`, `verify.ex`, `info.ex`, the installer, the composition test
  and `LICENSE` (ash-extension-pack), plus `mix.exs`, `.formatter.exs` (now with
  `AshGraphLaw.Formatter`), `.gitignore`, `README.md`, the root API, `ABI`, `Receipt`, `Admitted`,
  `Standing`, `Refusal`, `MANIFEST.json`, `test_helper.exs` and the typed-refusal reference.
- Release workflow re-runs every CI gate, admits only main or a `v*` tag, and checks the tag/version
  identity in the job that publishes. The manufacture workflow no longer cancels main runs.

### Known limits

- The installer's `--target` mode raises a `SyntaxError` (pack defect, `UNSUPPORTED(generator-capability)`).
- The pinned `graphlaw.wasm` was not fetched in the environment that produced this change, so the
  `:wasm` tests are unexecuted and the import allowlist is unconfirmed against the pinned asset.

## [26.9.29]

Initial release of the source-of-truth layout. Earlier work existed only as a heredoc inside a
manufacture workflow on a feature branch; committed ontology, queries and templates replace it.

### Added

- `AshGraphLaw.Resource` Spark extension with a `graphlaw` section: singleton `runtime` entity
  (`wasm_path`, `timeout_ms`, `max_skew_secs`, `trusted_keys`) and `admission` entities (`name`,
  `step`, `ceiling`, `law`, `projection`), plus `AshGraphLaw.Resource.Persist`,
  `AshGraphLaw.Resource.Verify` and `AshGraphLaw.Resource.Info`.
- `AshGraphLaw.Contract`, the verifier delegate that checks duplicate admissions, law modules for
  steps that need a payload, trusted key format and runtime option ranges.
- WASM host: `AshGraphLaw.Host`, `AshGraphLaw.Pool`, `AshGraphLaw.EngineLoad`,
  `AshGraphLaw.WasmConfig` and `AshGraphLaw.Application`. The engine is admitted (import surface,
  required exports, SHA-256 pin) before instantiation.
- Ash integration: `AshGraphLaw.Change.Admit`, `AshGraphLaw.Validation.Admissible`,
  `AshGraphLaw.Preparation.Admit`, `AshGraphLaw.Error.Refused`, `AshGraphLaw.Admissions`,
  `AshGraphLaw.Law` and `AshGraphLaw.Projection` behaviours with `AshGraphLaw.Projection.Default`,
  and `AshGraphLaw.Evidence`.
- Generated API modules: `AshGraphLaw`, `AshGraphLaw.ABI`, `AshGraphLaw.Receipt`,
  `AshGraphLaw.Admitted`, `AshGraphLaw.Standing` and `AshGraphLaw.Refusal` with a closed refusal
  code table.
- Mix tasks: `mix ash_graphlaw.install` (Igniter installer, generated), `mix ash_graphlaw.vendor`,
  `mix ash_graphlaw.verify` and `mix ash_graphlaw.mutate`.
- Diataxis documentation, `usage-rules.md`, `AGENTS.md`, and repository metadata (`SECURITY.md`,
  `CONTRIBUTING.md`, REUSE compliance, Dependabot, CODEOWNERS, CI workflows).

### Generation provenance

- GraphLaw release `v26.9.28`, ABI version 1, `graphlaw.wasm` SHA-256
  `30f6bc6eca9d125fe805f4c2643818ebb0a1471edec75ed0ed989c734397c645`.
- ggen `ff96f04e8c7b851e5cca53f3faf5ce1d5f43ce6e`, ggen-marketplace
  `caa4fe6133445638cbfdbfac017187ed8090dc95` (`ash-extension-pack`). These pins live in
  `ontology.ttl` and may be updated there by the integration step.
- Generated files are projections of `ontology.ttl`; the remaining modules are hand-written and
  marked `UNSUPPORTED(generator-capability)` because no listed pack emits them.
