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
| `AshGraphLaw.Resource`, `.Dsl.Runtime`, `.Dsl.Admission` | `lib/ash_graphlaw/resource.ex` | GENERATED (ash-extension-pack) |
| `AshGraphLaw.Resource.Persist`, `.Verify`, `.Info` | `persist.ex`, `verify.ex`, `info.ex` | GENERATED (ash-extension-pack) |
| `test/ash_graphlaw_composition_test.exs`, `LICENSE` | repo | GENERATED (ash-extension-pack) |
| `Mix.Tasks.AshGraphlaw.Install` | `lib/mix/tasks/ash_graphlaw.install.ex` | GENERATED (ash-extension-pack) |
| `AshGraphLaw`, `.ABI`, `.Refusal`, `.Receipt`, `.Admitted`, `.Standing` | `lib/ash_graphlaw*.ex` | GENERATED (local templates) |
| `mix.exs`, `.formatter.exs`, `.gitignore`, `README.md`, `priv/graphlaw/MANIFEST.json`, `test/test_helper.exs` | repo root | GENERATED (local templates) |
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

## Ops exposed

| Op | Surface |
|---|---|
| `law` | `AshGraphLaw.law/3`; the admission path used by Change, Validation and Preparation |
| `hooks` | `AshGraphLaw.hooks/3` |
| `capabilities` | `AshGraphLaw.capabilities/1`; used for the ABI check |
| `sniff` | `AshGraphLaw.sniff/3` |
| any other op (`parse`, `convert`, `canonical`, `sparql`, `shacl`, `shex`, `n3`, `entail`, `datalog`; `policy` is not in the pinned engine capabilities) | `AshGraphLaw.call/2` with a raw request map; no dedicated wrapper |

## Law steps supported in admissions

`shacl`, `n3`, `rdfs`, `owl_rl`, `hooks`, `plan`, `require_receipt`, `require_signed_receipt`.
`UNSUPPORTED(engine-capability)`: the pinned v26.9.28 engine refuses `plan`, `require_receipt`,
`require_signed_receipt` and `record-receipts` as `Unsupported` unknown steps; only `shacl`, `n3`,
`rdfs`, `owl_rl` and `hooks` are executed. `record-receipts` is an engine step available through raw `law` requests; the DSL does not
expose it as an `admission` step.

## Ash integration points

| Point | Supported |
|---|---|
| `change` on create, update, destroy | yes (`AshGraphLaw.Change.Admit`) |
| `validate` | yes (`AshGraphLaw.Validation.Admissible`); pass/fail, no evidence |
| `prepare` on read queries and generic-action input | yes (`AshGraphLaw.Preparation.Admit`) |

## Not supported

| Capability | Standing | Reason |
|---|---|---|
| Reactor middleware / workflow reactor | UNSUPPORTED | Not built; pack spec sets `workflowReactor false` |
| Atomic actions | UNSUPPORTED | Admission needs a WASM call; `atomic/3` returns `{:not_atomic, ...}` |
| Engine-side lease verification (signature, signer, expiry) | UNSUPPORTED | `UNSUPPORTED(engine-capability)`: the pinned v26.9.28 engine ignores lease keys and stamps no `lease_id`; only the library's ceiling pre-check on the claimed ceiling is enforced |
| Lease signing | UNSUPPORTED | The library verifies via the engine; it never issues or signs leases. Key custody is outside the library |
| Installer `--target` patching | UNSUPPORTED | The pack's generated installer inserts unparsable code (SyntaxError); the formatter and `wasmex` wiring work |
| Receipt persistence | UNSUPPORTED | Evidence lives in changeset context; no store is written |
| Executing consequences | UNSUPPORTED | Admission is observation; nothing is actuated |
| Bundled wasm binary | UNSUPPORTED | Fetched and digest-checked by `mix ash_graphlaw.vendor` |
| `wasm32-unknown-unknown` engines | UNSUPPORTED | Upstream requires a WASI host |
| Unpinned engine builds | refused | Digest mismatch is `:wasm_digest_mismatch` unless the caller supplies `expected_sha256`; a pinned load is judged on the digest before the bytes are compiled |
| WASI imports outside the manifest allowlist | refused | `:wasm_import_surface_mismatch` names each offending `module.function`; the allowlist is `glx:WasiImport` rows in `ontology.ttl` |
| Self-granted ceilings | refused | Only a signed lease raises authority above `:observe`; see [authority boundary](../topics/authority_boundary.md) |

## See Also

- [Claims and evidence](claims_and_evidence.md)
- [DSL reference](dsl_reference.md)
- [ABI reference](abi_reference.md)
