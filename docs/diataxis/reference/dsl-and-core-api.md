<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Reference: DSL and Core API

Version 26.10.1. Every entry below was verified against `lib/` in
`/Users/sac/ash_graphlaw`; file paths are given per entry. Semantics stay in GraphLaw; this
library exposes, it never reimplements.

## Root module — `lib/ash_graphlaw.ex`

| Function | Signature | Notes |
|---|---|---|
| `abi_version/0` | `() :: 1` | Compiled in from the ontology (`@abi_version`). |
| `graphlaw_release/0` | `() :: String.t()` | Engine release pin (for example `"v26.9.29"`). |
| `call/2` | `(request :: map(), opts) :: result` | Raw JSON-ABI call; `request` is a map with an `"op"` key. |
| `capabilities/1` | `(opts)` | Wraps `%{"op" => "capabilities"}`. |
| `sniff/3` | `(text, hint \\ nil, opts)` | Sniffs RDF text for a dialect hint. |
| `law/3` | `(data, steps, opts)` | Runs law steps against projected graph data. |
| `hooks/3` | `(data, pack, opts)` | Runs a hooks pack against graph data. |

Generated typed delegates for every registry op also exist: `parse/2 convert/2 canonical/2
sparql/2 shacl/2 shex/2 n3/2 entail/2 datalog/2 policy/2` and their bang forms (for example
`AshGraphLaw.sparql!(data: turtle, query: q)`). Generated from the capability registry through
the `graphlaw-ash-capability-pack`; `AshGraphLaw.Capability.Registry.names/0` lists the ops in
ABI order (`lib/ash_graphlaw/capability/registry.ex`, 14 ops at ABI 1). Unknown response fields
decode without failing; refusals keep the whole engine error in `refusal.raw`.

## Spark extension — `lib/ash_graphlaw/resource.ex`

`use Ash.Resource, extensions: [AshGraphLaw.Resource]` adds a `graphlaw` section with:

### `runtime` block

`wasm_path`, `timeout_ms` (default 5000), `max_skew_secs` (default 60), `trusted_keys`
(hex-encoded 32-byte public keys). Options verified in the `@runtime` entity schema.

### `admission/2`

- `:name` — required unique atom.
- `:step` — required, one of `:shacl, :n3, :rdfs, :owl_rl, :hooks, :plan, :require_receipt,
  :require_signed_receipt`.
- `:ceiling` — `:observe | :select | :construct`, default `:construct`.
- `:law` — optional module implementing `AshGraphLaw.Law`.
- `:projection` — optional module implementing `AshGraphLaw.Projection` (default
  `AshGraphLaw.Projection.Default`).

### `capability/2`

Declares that the resource uses a registry op (for example `:sparql`, `:shacl`); `:ceiling`
defaults to `:observe` and must not be below what the op needs (`:construct` for `n3`, `entail`,
`datalog`, `hooks`, `law`). Declaring a ceiling never grants authority.

## Core modules

### `AshGraphLaw.Admissions` — `lib/ash_graphlaw/admissions.ex`

- `all/1`, `fetch/2` — declared admissions on a resource.
- `runtime/1` — the resource's `runtime` options.
- `capabilities/1`, `capability/2`, `declared?/2` — declared capabilities.

### `AshGraphLaw.Authority` — `lib/ash_graphlaw/authority.ex`

- `claim/1` — reads the authority claim from a lease.
- `check_ceiling/2` — compares an admission's ceiling with a lease (order
  `:observe < :select < :construct`); `:observe` admissions pass with no lease.
- `op_ceiling/1` — the ceiling an op needs (`:observe` for read-only ops, `:construct` for
  `n3`, `entail`, `datalog`, `hooks`, `law`).
- `check_op/3` — op authority check against a policy.
- `engine_opts/3` — merges resource runtime + lease into engine options.
- `identity/1` — lease identity.

### `AshGraphLaw.Law` — `lib/ash_graphlaw/law.ex`

Behaviour for law modules. Required callback `steps/2` returning `[map()]` with string keys
(the engine `law` op step format); optional `data/2` returning `{:ok, %{text: t, dialect: d}}`
or `:default` to override the projected graph. A raise becomes the typed
`:law_module_failed` refusal. Dispatch helpers `Law.data/3` fall back to the admission's
projection when `data/2` is not exported.

### `AshGraphLaw.Projection.Default` — `lib/ash_graphlaw/projection/default.ex`

Deterministic N-Triples projection. Subject IRI
`<urn:ash-graphlaw:resource:{Module}:{pk-or-new}>`; emits `ag:action`, `ag:actionType`, one
`ag:attr:{name}` per non-nil attribute, one `ag:arg:{name}` per non-nil argument, `ag:atom`
markers, and query summaries (`ag:query:filter`, `ag:query:sort`, `ag:query:limit`,
`ag:query:offset`). Sensitive attributes/arguments (`sensitive?: true`) are never projected.
Output is de-duplicated and sorted, so identical input yields byte-identical text. Invalid
subjects return `{:error, %AshGraphLaw.Refusal{code: :projection_failed}}`.

### `AshGraphLaw.Refusal` — `lib/ash_graphlaw/refusal.ex`

Exception struct with fields `code, class, kind, engine, dialect, message, details, broken_term,
raw`. Introspection: `codes/0` (every code, in ontology order), `classes/0`,
`broken_terms/0`, `class_of/1` (code to one of `:refused_admission, :refused_authority,
:blocked_resource, :refused_structure, :unsupported, :refused_identity`), `broken_term_of/1`
(code to a Chatman failure-taxonomy term: `:mu_on_O, :R_missing_authority, :R_missing_consequence,
:R_missing_standing, :R_missing_identity, :admission_vacuous`). Unknown code to `class_of/1`
raises `ArgumentError`.

Common pairings: `:host_not_started` → `:blocked_resource`; `:ceiling_unmet` →
`:refused_authority`; `:not_admitted` → `:refused_admission` (broken term `:mu_on_O`);
`:abi_version_mismatch` → `:refused_identity`.

### `AshGraphLaw.Admitted` — `lib/ash_graphlaw/admitted.ex`

Struct `:states, :receipts, :nquads, :raw`. `Admitted.from_map/1` builds from a string-keyed
engine map; missing fields default to `[]`, `[]`, `""`. An observation of one exact input; it
never stores standing.

### `AshGraphLaw.Receipt` — `lib/ash_graphlaw/receipt.ex`

Struct `:step, :parent, :child, :added, :authority, :revision, :lease_id, :plan_sha256, :index,
:raw`. `Receipt.from_map/1` never raises on a map; unknown keys survive in `:raw`.

### `AshGraphLaw.Standing` — `lib/ash_graphlaw/standing.ex`

`all/0`, `valid?/1`, `describe/1` over `:UNKNOWN, :PARTIAL_ALIVE, :ALIVE, :BLOCKED,
:BUILD_BROKEN, :UNSUPPORTED`. `Standing.of/1` maps a result to standing: `{:ok, %Admitted{}}`
→ `:PARTIAL_ALIVE` (never `:ALIVE` — admission alone is an observation, not authority);
`{:error, %Refusal{class: :blocked_resource}}` → `:BLOCKED`; `{:error,
%Refusal{class: :unsupported}}` → `:UNSUPPORTED`; any other `{:error, %Refusal{}}` →
`:UNKNOWN`; anything else → `:UNKNOWN`.

## Mix tasks

`mix ash_graphlaw.vendor` (`--check`, `--from PATH`) — download and digest-verify the engine;
`mix ash_graphlaw.verify` — digest pin + import allowlist + required exports + one live
`capabilities` call; `mix ash_graphlaw.parity` — fails on drift between the live engine, the
vendored registry and the Elixir surface. Task names verified in `mix.exs` aliases and
`documentation/tutorials/getting_started.md`.

## Configuration — `config/config.exs`

- `config :ash_graphlaw, start_pool: true` — start `AshGraphLaw.Pool` at boot.
- `config :ash_graphlaw, pool: [size: 4, timeout_ms: 5_000]` — pool size and per-call timeout.
