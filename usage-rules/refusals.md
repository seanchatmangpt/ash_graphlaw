<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Refusals

Every failure is an `%AshGraphLaw.Refusal{}` with `code`, `class`, `kind`, `engine`,
`dialect`, `message`, `details`, `broken_term`. The code set is closed.
`AshGraphLaw.Refusal.codes/0` lists it. The reference table is generated at
`documentation/reference/typed_refusals.md`.

## Classes

`refused_identity`, `refused_structure`, `refused_authority`, `refused_admission`,
`blocked_resource`, `unsupported`.

## Codes

| Source | Code : class |
|---|---|
| engine | `not_admitted`, `plan_refused`, `receipt_required`, `policy_refused` : refused_admission |
| engine | `lease_refused` : refused_authority |
| engine | `resource_limit` : blocked_resource |
| engine | `engine_refused` : refused_structure; `engine_unclassified` : unsupported |
| host | `wasm_not_vendored wasm_unreadable instantiation_failed abi_failure call_trapped` : blocked_resource |
| host | `call_exited call_timeout saturated host_not_started fuel_exhausted` : blocked_resource |
| host | `wasm_digest_mismatch wasm_import_surface_mismatch abi_version_mismatch` : refused_identity |
| host | `wasm_invalid wasm_missing_export invalid_encoding invalid_json malformed_response` : refused_structure |
| ash | `unknown_admission duplicate_admission missing_law_module invalid_runtime_option` : refused_structure |
| ash | `invalid_trusted_key projection_failed law_module_failed` : refused_structure |
| ash | `ceiling_unmet` : refused_authority; `unsupported_step` : unsupported |

Each code carries a `broken_term` from the Chatman taxonomy (`mu_on_O`, `admission_vacuous`,
`R_missing_identity`, `R_missing_authority`, `R_missing_consequence`, `R_missing_replay`,
`R_missing_standing`, `mu_unlawful`). Digest, import and ABI-version codes map to
`:R_missing_identity`; `lease_refused` and `ceiling_unmet` to `:R_missing_authority`;
`not_admitted`, `plan_refused`, `policy_refused`, `receipt_required` to `:mu_on_O`. Others
are assigned in `ontology.ttl`.

## Handling rules

- Do match on `code`, `class`, or `broken_term`. Never on `message`.
- Do keep `from_engine/2` total: engine enums are non-exhaustive, so an unknown future
  variant becomes `:engine_unclassified`, never a crash.
- Do not add a code in hand-written code. Add a row to `ontology.ttl` and regenerate.
- Do not retry `refused_*` classes; the same input will be refused again. `blocked_resource`
  may be retried after the resource condition changes.

## Standing

Vocabulary: `:UNKNOWN :PARTIAL_ALIVE :ALIVE :BLOCKED :BUILD_BROKEN :UNSUPPORTED`.
`AshGraphLaw.Standing.of/1`:

| Result | Standing |
|---|---|
| `{:ok, %Admitted{}}` | `:PARTIAL_ALIVE` (consequence not executed; never `:ALIVE`) |
| `{:error, %Refusal{class: :blocked_resource}}` | `:BLOCKED` |
| `{:error, %Refusal{class: :unsupported}}` | `:UNSUPPORTED` |
| any other refusal, or anything else | `:UNKNOWN` (typed refusal is on the `%Refusal{}`) |

Standing is derived, never stored.

## See Also

[admission.md](admission.md) - [wasm-host.md](wasm-host.md) - [../usage-rules.md](../usage-rules.md)
