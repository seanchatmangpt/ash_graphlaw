<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses calendar versioning
(`YY.M.N`).

## [26.10.1] - 2026-10-01

First Hex publish. Version bump carrying the prior-art vocabulary bindings and the parity court
hardening landed after 26.9.30. GraphLaw engine pin unchanged: `v26.9.29` (wasm SHA-256
`7bb2a7e5...`, ABI version 1).

### Added

- Prior-art vocabulary bindings under `priv/prior_art/`: RDF 1.1 graph semantics
  (`rdf_1_1_import.json`), RDFS 1.1 vocabulary semantics (`rdfs_1_1_import.json`) and the PROV-O
  projection ceiling (`prov-o-rec-20130430.json`) — the external vocabularies the admission graph
  is allowed to project into, pinned by their normative documents.

### Fixed

- Reference documentation (ABI, DSL, support matrix) now describes the pinned v26.9.29 engine
  instead of the retired v26.9.28 gap set: every law step (including `plan`, `require_receipt`,
  `require_signed_receipt`) executes, SHACL violations surface as `:not_admitted`, depth overrun
  as `:resource_limit`, and signed leases are verified engine-side with receipts stamped
  `lease_id`.

### Tests

- Parity court bound to the pinned runtime ABI: cross-runtime ABI drift fixture, parity R2
  refuses manifest ABI drift.

### Manufacture

- Marketplace pin re-anchored to the pushed `86735f4e` (pack emits the fixed installer), with
  `CITATION.cff` and `engineering-standards.json` added as version-bound projections.

## [26.9.30] - 2026-09-30

Version bump for the 26.9.30 Hex release dry run. The typed capability surface below ships in this
release; the GraphLaw engine pin is `v26.9.29` (wasm SHA-256 `7bb2a7e5...`, ABI version 1).

### Added (typed capability surface, v26.9.29 target)

- Typed capability surface: `AshGraphLaw.Capability.<Op>` for all 14 GraphLaw ops (capabilities,
  sniff, parse, convert, canonical, sparql, shacl, shex, n3, entail, datalog, hooks, law, policy),
  `AshGraphLaw.Capability.API` (`<op>/2` and `<op>!/2`), `AshGraphLaw.Capability.Registry` and
  lossless `AshGraphLaw.Result.*` structs plus `AshGraphLaw.Result.Term`. Generated from the
  GraphLaw capability registry (`graphlaw.capability-registry/1`) through the
  `graphlaw-ash-capability-pack`; no supported op needs `AshGraphLaw.call/2`. Root delegates
  `parse/2 convert/2 canonical/2 sparql/2 shacl/2 shex/2 n3/2 entail/2 datalog/2 policy/2` and bang
  forms; `call/2`, `capabilities/1`, `sniff/3`, `law/3` and `hooks/3` are unchanged.
- Registry import: `scripts/vendor_registry.sh` and `scripts/import_registry.sh` (both with
  `--check`), and `priv/graphlaw/capability-registry.{json,ttl}` plus `op-examples.json`.
- DSL: new `capability` entity in the `graphlaw` section (`name`, `ceiling`, `doc`). A resource
  declaring at least one capability refuses undeclared ops in lifecycle modules with
  `:capability_not_declared`; a resource declaring none allows all. The `admission` entity, its
  steps and `Change.Admit`, `Validation.Admissible`, `Preparation.Admit` are unchanged.
- Parity court: `mix ash_graphlaw.parity [--evidence-dir DIR]` (checks P1-P9) and
  `AshGraphLaw.Parity.run/1`; CI runs it in a `parity` job that gates `test`.
- Lifecycle modules: `AshGraphLaw.Lifecycle`,
  `AshGraphLaw.Calculation.{Conforms,CanonicalId,Sparql}`, `AshGraphLaw.Validation.Shacl`, `AshGraphLaw.Change.Canonicalize`.
- Reactor: `AshGraphLaw.Reactor`, `AshGraphLaw.Reactor.Hooks`, `AshGraphLaw.Reactor.Capability`,
  compiled only when `Reactor.Step` is loadable; `reactor` is an optional dependency.
- Telemetry: `[:ash_graphlaw, :capability, :start | :stop | :exception]` with `op`, `outcome`,
  `refusal_code` and `server` metadata; `[:ash_graphlaw, :admission, :stop]` is unchanged.
- Projection origins: `AshGraphLaw.Projection.Origin`.
- `AshGraphLaw.Refusal` gains `:raw` (the whole engine error map, `nil` for client-side refusals)
  and `AshGraphLaw.Refusal.build/3`; `from_engine/2` keeps its signature and mapping.
- Five new typed refusal codes (36-40): `:invalid_capability_request`, `:unknown_capability`,
  `:capability_not_declared`, `:capability_parity_drift`, `:capability_response_undecodable`. The 35
  existing codes are unchanged.
- Docs: `documentation/reference/capabilities.md` and per-op pages; hexdocs groups `Typed
  capabilities`, `Lifecycle`, `Reactor`, `Telemetry`, `Parity`.

### Changed (build and CI)

- CI vendors the engine with one `mix ash_graphlaw.vendor` step per job, adds the `parity` job
  (evidence uploaded, gates `test`), and runs `scripts/vendor_registry.sh --check` and
  `scripts/import_registry.sh --check` in the `quality` job.
- The coverage gate now requires the mix.exs threshold to equal ontology `glx:coverageThreshold`
  (80) and to be at least 80.

### Engine pin

- The engine pin moves to GraphLaw `v26.9.29` (ABI version 1), `graphlaw.wasm` SHA-256
  `7bb2a7e5ebcef7584b0b960451272d56fa75414d76a12138d41e8973e126eee0`, a published release asset
  (`ontology.ttl` is the source; `priv/graphlaw/MANIFEST.json` and `lib/ash_graphlaw.ex` carry it).
  The engine now implements the `plan`, `require-receipt` and signed-lease steps, reports a SHACL
  violation as `NotAdmitted` (`:not_admitted`) and reports a depth/size cap as `ResourceLimit`
  (`:resource_limit`, `details.limit` names the cap: `json_depth`, `plan_total_atoms`,
  `n3_derived_facts`, ...). The tests that pinned the old engine's gaps now assert the new behavior.

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
