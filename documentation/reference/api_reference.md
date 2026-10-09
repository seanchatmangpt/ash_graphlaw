<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# api_reference

Public modules and functions. Provenance (`GENERATED` or `HAND`) per module is in the
[support matrix](support_matrix.md). Signatures below were read from source on the working tree;
function docs are in the module docs (`mix docs`).

## Root API: `AshGraphLaw`

| Function | Returns |
|---|---|
| `call/2` | `{:ok, map}` or `{:error, %Refusal{}}` for any raw request map |
| `capabilities/1`, `sniff/3`, `law/3`, `hooks/3` | legacy wrappers; unchanged return shapes |
| `parse/2`, `convert/2`, `canonical/2`, `sparql/2`, `shacl/2`, `shex/2`, `n3/2`, `entail/2`, `datalog/2`, `policy/2` | typed; delegate to `AshGraphLaw.Capability.API` |
| the same ten with a `!` suffix | raise `AshGraphLaw.Error.Refused` |
| `engine_sha256/1`, `abi_version/0`, `graphlaw_release/0` | pin and engine identity |

## Typed capability surface (generated)

| Module | Role |
|---|---|
| `AshGraphLaw.Capability` | behaviour: `op/0`, `build_request/1`, `decode/1`, `run/2` |
| `AshGraphLaw.Capability.<Op>` (14) | `op/0`, `fields/1`, `build_request/1`, `decode/1`, `run/2` |
| `AshGraphLaw.Capability.API` | `<op>/2`, `<op>!/2` for each op, `run/3` by name |
| `AshGraphLaw.Capability.Registry` | `schema/0`, `graphlaw_version/0`, `abi_version/0`, `digest/0`, `surface_digest/0`, `names/0`, `ops/0`, `op/1`, `module_for/1`, `rdf_dialects/0`, `other_dialects/0`, `law_steps/0`, `refusal_codes/0`, `limits/0`, `regimes/0` |
| `AshGraphLaw.Result.<Op>` (13) | struct with one key per response field, `:raw`, and `:kind` for tagged ops; `from_map/1` |
| `AshGraphLaw.Result.Term` | type, value, datatype, lang, raw |

`law` decodes to `AshGraphLaw.Admitted`. Per-op pages are generated:
[capabilities.md](capabilities.md).

## Typed capability helpers (hand-written)

| Module | Role |
|---|---|
| `AshGraphLaw.Capability.CanonicalJSON` | `encode/1`, `sha256/1`, `digest/1`, `surface_digest/1` |
| `AshGraphLaw.Capability.Coerce` | `request/3`, `stringify/1`: argument normalization and validation |
| `AshGraphLaw.Capability.Decode` | `ensure_map/1`, `value/2`, `variant/3`, `get/3` |
| `AshGraphLaw.Telemetry` | `capability/3`, `events/0`; see [telemetry](telemetry.md) |
| `AshGraphLaw.Parity` | `run/1`, `checks/0`, `check_ids/0`, `write_report/2` |
| `AshGraphLaw.Reactor` | `available?/0` |
| `AshGraphLaw.Reactor.Hooks`, `.Capability` | Reactor steps (optional `:reactor`) |

## Ash integration

| Module | Kind |
|---|---|
| AshGraphLaw.Resource | Spark extension; sections `runtime`, `admission`, `capability` |
| `AshGraphLaw.Change.Admit`, `.Change.Canonicalize` | Ash changes |
| `AshGraphLaw.Validation.Admissible`, `.Validation.Shacl` | Ash validations |
| `AshGraphLaw.Preparation.Admit` | Ash preparation |
| `AshGraphLaw.Calculation.Conforms`, `.CanonicalId`, `.Sparql` | Ash calculations |
| `AshGraphLaw.Lifecycle` | shared plumbing of the lifecycle modules |
| `AshGraphLaw.Admissions` | `all/1`, `fetch/2`, `runtime/1`, `capabilities/1`, `capability/2`, `declared?/2` |
| `AshGraphLaw.Authority` | `claim/1`, `check_ceiling/2`, `op_ceiling/1`, `check_op/3`, `engine_opts/3`, `identity/1` |

## Values

| Module | Role |
|---|---|
| `AshGraphLaw.Refusal` | typed refusal: code, class, kind, engine, dialect, message, details, broken_term, raw; new/3, build/3, from_engine/2, codes/0 |
| `AshGraphLaw.Error`, `.Error.Refused` | Splode error wrapper; `refusals/1`, `codes/1`, `refused?/1` |
| `AshGraphLaw.Admitted`, `.Receipt`, `.Standing` | law result, receipt, derived standing |
| `AshGraphLaw.Evidence`, `.Projection.Origin` | admission evidence and projection provenance |
| `AshGraphLaw.Projection`, `.Projection.Default`, `AshGraphLaw.Law` | behaviours and default projection |

## Engine host

| Module | Role |
|---|---|
| `AshGraphLaw.Host` | one supervised Wasmtime instance |
| `AshGraphLaw.Pool` | N hosts behind one name |
| `AshGraphLaw.EngineLoad` | digest, import and export admission of the bytes |
| `AshGraphLaw.WasmConfig` | path resolution, pin, limits |
| `AshGraphLaw.ABI` | wire codec |

## Mutation court

`AshGraphLaw.Mutation`, `.Mutation.Catalog`, `.Collector`, `.Runner`, `.Verdict`; driven by
`mix ash_graphlaw.mutate`.

## See Also

- [Support matrix](support_matrix.md)
- [DSL reference](dsl_reference.md)
- [Configuration](configuration.md)
