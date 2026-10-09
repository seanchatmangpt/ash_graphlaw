<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# support_matrix

What is generated, what is hand-written, and what is not supported. Provenance labels:
`GENERATED` (ggen projection; never hand-edited), `HAND` (irreducible residue, labeled
`UNSUPPORTED(generator-capability)` in the file), `TOOL` (derived by a mix task).

## Modules

| Module | File | Provenance |
|---|---|---|
| AshGraphLaw.Resource, .Dsl.Runtime, .Dsl.Admission | `lib/ash_graphlaw/resource.ex` | GENERATED (ash-extension-pack) |
| `AshGraphLaw.Resource.Persist`, `.Verify`, `.Info` | lib/ash_graphlaw/persist.ex, lib/ash_graphlaw/verify.ex, lib/ash_graphlaw/info.ex | GENERATED (ash-extension-pack) |
| test/ash_graphlaw_composition_test.exs, LICENSE | repo | GENERATED (ash-extension-pack) |
| `Mix.Tasks.AshGraphlaw.Install` | `lib/mix/tasks/ash_graphlaw.install.ex` | GENERATED (ash-extension-pack) |
| `AshGraphLaw`, `.ABI`, `.Refusal`, `.Receipt`, `.Admitted`, `.Standing` | `lib/ash_graphlaw*.ex` | GENERATED (local templates) |
| `AshGraphLaw.Capability` (behaviour), `.Capability.Registry`, `.Capability.API`, `.Capability.<Op>` (14) | `lib/ash_graphlaw/capability*.ex` | GENERATED (graphlaw-ash-capability-pack) |
| `AshGraphLaw.Result.Term`, `.Result.<Op>` (13) | `lib/ash_graphlaw/result/*.ex` | GENERATED (graphlaw-ash-capability-pack) |
| `documentation/reference/capabilities.md`, `capabilities/<op>.md` (14), `test/generated/capability_surface_test.exs` | | GENERATED (graphlaw-ash-capability-pack) |
| `AshGraphLaw.Capability.CanonicalJSON`, `.Coerce`, `.Decode` | `lib/ash_graphlaw/capability/` | HAND |
| `AshGraphLaw.Telemetry`, `.Lifecycle`, `.Parity`, `mix ash_graphlaw.parity` | `lib/` | HAND |
| `AshGraphLaw.Calculation.{Conforms,CanonicalId,Sparql}`, `.Validation.Shacl`, `.Change.Canonicalize`, `.Projection.Origin` | `lib/ash_graphlaw/` | HAND |
| `AshGraphLaw.Reactor`, `.Reactor.Hooks`, `.Reactor.Capability` | `lib/ash_graphlaw/reactor*` | HAND (optional `:reactor`) |
| mix.exs, .formatter.exs, .gitignore, README.md, priv/graphlaw/MANIFEST.json, test/test_helper.exs | repo root | GENERATED (local templates) |
| `documentation/reference/typed_refusals.md` | | GENERATED |
| `documentation/dsls/DSL-AshGraphLaw.Resource.md` | | TOOL (`mix spark.cheat_sheets`) |
| `scripts/ggen_sync.sh`, `scripts/vendor_marketplace.sh` | `scripts/` | HAND (pack has no consumer-side scoping; see [generation and residue](../topics/generation_and_residue.md)) |
| `AshGraphLaw.Host`, `.Pool`, `.EngineLoad`, `.WasmConfig`, `.Application` | `lib/ash_graphlaw/` | HAND |
| `AshGraphLaw.Admissions`, `.Authority`, `.Contract`, `.Formatter`, `.CheatSheet` | `lib/ash_graphlaw/` | HAND |
| `AshGraphLaw.Law`, `.Projection`, `.Projection.Default`, `.Evidence` | `lib/ash_graphlaw/` | HAND |
| `AshGraphLaw.Error`, `.Error.Refused` | `lib/ash_graphlaw/error*` | HAND |
| `AshGraphLaw.Change.Admit`, `.Validation.Admissible`, `.Preparation.Admit` | `lib/ash_graphlaw/` | HAND |
| `AshGraphLaw.Mutation*`, `mix ash_graphlaw.{vendor,verify,mutate}` | `lib/` | HAND |
| Tests, prose docs, usage rules, workflows, config | various | HAND |

Why hand-written: no listed pack emits Spark transformer injection into actions, a Wasmex host,
Ash Change/Validation/Preparation modules, a Splode error, or a mutation engine. See
[generation and residue](../topics/generation_and_residue.md).

## Ops exposed: 14-op parity table

Every op in the registry has a typed module, a result struct and a function on
`AshGraphLaw.Capability.API`. Root function: the function on `AshGraphLaw`. Legacy: the root
function keeps its pre-26.9.29 return shape, and the typed form lives only on
`AshGraphLaw.Capability.API`. Ceiling: the minimum `capability` ceiling
(`AshGraphLaw.Authority.op_ceiling/1`). Labels: the typed module, result struct and root delegate
are `GENERATED`; the ceiling table is `HAND` (`authority.ex`).

| # | Op | Typed module | Result struct | Root function | Ceiling | Legacy | Label |
|---|---|---|---|---|---|---|---|
| 1 | `capabilities` | `AshGraphLaw.Capability.Capabilities` | `AshGraphLaw.Result.Capabilities` | `capabilities/1` | observe | yes | GENERATED / HAND |
| 2 | `sniff` | `AshGraphLaw.Capability.Sniff` | `AshGraphLaw.Result.Sniff` | `sniff/3` | observe | yes | GENERATED / HAND |
| 3 | `parse` | `AshGraphLaw.Capability.Parse` | `AshGraphLaw.Result.Parse` | `parse/2` | observe | no | GENERATED / HAND |
| 4 | `convert` | `AshGraphLaw.Capability.Convert` | `AshGraphLaw.Result.Convert` | `convert/2` | observe | no | GENERATED / HAND |
| 5 | `canonical` | `AshGraphLaw.Capability.Canonical` | `AshGraphLaw.Result.Canonical` | `canonical/2` | observe | no | GENERATED / HAND |
| 6 | `sparql` | `AshGraphLaw.Capability.Sparql` | `AshGraphLaw.Result.Sparql` | `sparql/2` | observe | no | GENERATED / HAND |
| 7 | `shacl` | `AshGraphLaw.Capability.Shacl` | `AshGraphLaw.Result.Shacl` | `shacl/2` | observe | no | GENERATED / HAND |
| 8 | `shex` | `AshGraphLaw.Capability.Shex` | `AshGraphLaw.Result.Shex` | `shex/2` | observe | no | GENERATED / HAND |
| 9 | n3 | `AshGraphLaw.Capability.N3` | `AshGraphLaw.Result.N3` | `n3/2` | construct | no | GENERATED / HAND |
| 10 | `entail` | `AshGraphLaw.Capability.Entail` | `AshGraphLaw.Result.Entail` | `entail/2` | construct | no | GENERATED / HAND |
| 11 | `datalog` | `AshGraphLaw.Capability.Datalog` | `AshGraphLaw.Result.Datalog` | `datalog/2` | construct | no | GENERATED / HAND |
| 12 | `hooks` | `AshGraphLaw.Capability.Hooks` | `AshGraphLaw.Result.Hooks` | `hooks/3` | construct | yes | GENERATED / HAND |
| 13 | `law` | `AshGraphLaw.Capability.Law` | `AshGraphLaw.Admitted` (binding override) | `law/3` | construct | yes | GENERATED / HAND |
| 14 | `policy` | `AshGraphLaw.Capability.Policy` | `AshGraphLaw.Result.Policy` | `policy/2` | observe | no | GENERATED / HAND |

Whether every generated module exists on this tree is UNKNOWN until `scripts/ggen_sync.sh` has
run; whether the live engine agrees with this table is UNKNOWN until `mix ash_graphlaw.parity`
runs (see [claims and evidence](claims_and_evidence.md)). `call/2` remains for raw requests, and
`capabilities/1`, `sniff/3`, `law/3`, `hooks/3` and the admission DSL keep working.

## Law steps supported in admissions

`shacl`, `n3`, `rdfs`, `owl_rl`, `hooks`, `plan`, `require_receipt`, `require_signed_receipt`.
All of them execute on the pinned v26.9.29 engine. `record-receipts` is an engine step available through raw `law` requests; the DSL does not
expose it as an `admission` step.

## Capability lifecycle modules

| Module | Op | Atomic |
|---|---|---|
| `AshGraphLaw.Validation.Shacl` | `shacl` | not applicable |
| `AshGraphLaw.Change.Canonicalize` | `canonical` | no (`{:not_atomic, ...}`) |
| `AshGraphLaw.Calculation.Conforms` | `shacl` | no expression/2 |
| `AshGraphLaw.Calculation.CanonicalId` | `canonical` | no expression/2 |
| `AshGraphLaw.Calculation.Sparql` | `sparql` | no expression/2 |

## Ash integration points

| Point | Supported |
|---|---|
| `change` on create, update, destroy | yes (`AshGraphLaw.Change.Admit`) |
| `validate` | yes (`AshGraphLaw.Validation.Admissible`); pass/fail, no evidence |
| `prepare` on read queries and generic-action input | yes (`AshGraphLaw.Preparation.Admit`) |

## Not supported

| Capability | Standing | Reason |
|---|---|---|
| Reactor middleware | UNSUPPORTED | Steps exist (`AshGraphLaw.Reactor.Hooks`, `.Capability`), not middleware; pack spec sets `workflowReactor false` |
| Atomic actions | UNSUPPORTED | Admission needs a WASM call; `atomic/3` returns `{:not_atomic, ...}` |
| Caller-supplied lease material | UNSUPPORTED | The pinned v26.9.29 engine verifies signed leases itself (signature against trusted_keys, expiry on its own clock, receipts stamped with lease_id); library-side, trusted_keys and max_skew_secs come only from the resource runtime section, and caller-context now_unix, lease, unverified_lease are never forwarded |
| Lease signing | UNSUPPORTED | The library verifies via the engine; it never issues or signs leases. Key custody is outside the library |
| Installer `--target` patching | UNSUPPORTED | The pack's generated installer inserts unparsable code (SyntaxError); the formatter and wasmex wiring work |
| Receipt persistence | UNSUPPORTED | Evidence lives in changeset context; no store is written |
| Executing consequences | UNSUPPORTED | Admission is observation; nothing is actuated |
| Bundled wasm binary | UNSUPPORTED | Fetched and digest-checked by `mix ash_graphlaw.vendor` |
| `wasm32-unknown-unknown` engines | UNSUPPORTED | Upstream requires a WASI host |
| Unpinned engine builds | refused | Digest mismatch is `:wasm_digest_mismatch` unless the caller supplies `expected_sha256`; a pinned load is judged on the digest before the bytes are compiled |
| WASI imports outside the manifest allowlist | refused | :wasm_import_surface_mismatch names each offending module.function; the allowlist is glx:WasiImport rows in ontology.ttl |
| Self-granted ceilings | refused | Only a signed lease raises authority above `:observe`; see [authority boundary](../topics/authority_boundary.md) |

## See Also

- [Claims and evidence](claims_and_evidence.md)
- [DSL reference](dsl_reference.md)
- [ABI reference](abi_reference.md)
- [Capabilities](capabilities.md) (generated)
- [Conformance claim](conformance_claim.md)
