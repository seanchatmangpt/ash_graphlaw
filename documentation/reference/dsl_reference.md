<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# dsl_reference

The `graphlaw` section of the `AshGraphLaw.Resource` Spark extension. This page is the hand-written
companion to the generated cheat sheet, `documentation/dsls/DSL-AshGraphLaw.Resource.md` (written by
`mix spark.cheat_sheets`, and checked against this page field by field: names, types, defaults and
required flags agree); if they disagree, the generated cheat sheet (derived
from the compiled DSL) wins and this page has a bug.

## Enabling the extension

```elixir
use Ash.Resource,
  domain: MyApp.Domain,
  extensions: [AshGraphLaw.Resource]
```

The extension declares one section, `:graphlaw`. The section is optional: a resource that omits
it gets the struct defaults of `runtime` (see below), no admissions and no declared capabilities.

## Section `graphlaw`

| Item | Kind | Cardinality | Struct |
|---|---|---|---|
| `runtime` | entity | singleton (at most one) | `AshGraphLaw.Dsl.Runtime` |
| `admission` | entity | zero or more, unique by `name` | `AshGraphLaw.Dsl.Admission` |
| `capability` | entity | zero or more, unique by `name` | `AshGraphLaw.Dsl.Capability` |

```elixir
graphlaw do
  runtime do
    timeout_ms 5_000
  end

  admission :ticket_shape do
    step :shacl
    law MyApp.ShapeLaw
  end
end
```

## Entity `runtime`

Per-resource defaults for calls into the GraphLaw WASM engine. Takes no positional arguments.

| Field | Type | Default | Required | Meaning |
|---|---|---|---|---|
| `wasm_path` | `String.t()` | `nil` | no | Path to a `graphlaw.wasm` file. `nil` means the resolution order in `AshGraphLaw.WasmConfig` applies. |
| `timeout_ms` | `integer` | `5000` | no | Per-call timeout in milliseconds. Must be greater than 0. |
| `max_skew_secs` | `integer` | `60` | no | Largest tolerated lead of a signed lease's `issued_unix` over the verifier clock. Must be 0 or greater. |
| `trusted_keys` | `[String.t()]` | `[]` | no | Hex Ed25519 public keys trusted for signed leases and receipts. Each entry must be 64 hex characters. These are the ONLY trust anchors: caller context cannot add, replace or extend them. |

## Entity `admission`

A named admission: an ordered claim that a projected subject must pass one GraphLaw `law` step.
The single positional argument is `name`, which is also the entity identifier.

| Field | Type | Default | Required | Meaning |
|---|---|---|---|---|
| `name` | `atom` | none | yes | Unique within the resource. Actions refer to it by this atom. |
| `step` | `atom`, one of the values below | none | yes | The GraphLaw `law` step to run. |
| `ceiling` | `atom`, one of `:observe`, `:select`, `:construct` | `:construct` | no | Authority ceiling the caller's SIGNED lease must meet (`AshGraphLaw.Authority`); a bare atom grants only `:observe`. |
| `law` | `module` | `nil` | no | Module implementing `AshGraphLaw.Law`; supplies step payloads. |
| `projection` | `module` | `nil` | no | Module implementing `AshGraphLaw.Projection`; overrides the default projection. |

### `step` values

| Value | Engine step | Needs a `law` module |
|---|---|---|
| `:shacl` | `shacl` (shapes Turtle in the step map) | yes |
| `:n3` | `n3` (rules text) | yes |
| `:rdfs` | `rdfs` entailment | no |
| `:owl_rl` | `owl-rl` entailment | no |
| `:hooks` | `hooks` (knowledge-hook pack) | yes |
| `:plan` | `plan` (actions and goal) | yes |
| `:require_receipt` | `require-receipt` | yes |
| `:require_signed_receipt` | `require-signed-receipt` | yes |

The pinned v26.9.29 engine executes every step in the table, including `:plan`, `:require_receipt`
and `:require_signed_receipt`. An admission using one runs the engine step; a failure surfaces as
the mapped refusal (a SHACL violation as `:not_admitted`, a resource cap as `:resource_limit`).

The underscore atoms map to the hyphenated wire names. Step payload format is defined by the
GraphLaw ABI; see [ABI reference](abi_reference.md).

### `ceiling` values

The ceiling is checked against the lease in `changeset.context[lease_key]` before any engine
call; a shortfall is refused as `:ceiling_unmet`. `:observe` covers gates, `:select` covers
`plan`, `:construct` covers derivation steps. Above `:observe` the engine also verifies the
presented signed lease itself (signature against `trusted_keys`, expiry on the engine clock);
`trusted_keys` and `max_skew_secs` come only from the resource `runtime` section.

## Entity `capability`

Declares that the resource may run a typed GraphLaw op through the lifecycle modules
(`Validation.Shacl`, `Change.Canonicalize`, the calculations). The single positional argument is
`name`, also the entity identifier.

| Field | Type | Default | Required | Meaning |
|---|---|---|---|---|
| `name` | `atom` | none | yes | An op name in `AshGraphLaw.Capability.Registry.names/0`, for example `:sparql`. |
| `ceiling` | `atom`, one of `:observe`, `:select`, `:construct` | `:observe` | no | Ceiling this declaration carries. It must be at least `AshGraphLaw.Authority.op_ceiling/1` for the op: `:observe` for `capabilities sniff parse convert canonical sparql shacl shex policy`, `:construct` for `n3 entail datalog hooks law`. |
| `doc` | `String.t()` | `nil` | no | Description. |

```elixir
graphlaw do
  capability :shacl
  capability :hooks, ceiling: :construct
end
```

Semantics: a resource declaring at least one `capability` refuses any undeclared op in the
lifecycle modules with `:capability_not_declared`; a resource declaring none allows all (back
compatibility). When a lease is presented, its claimed ceiling must meet the declared ceiling, else
`:ceiling_unmet`. This check is a presentation check; the engine still verifies the lease.
`AshGraphLaw.Admissions.capabilities/1` and `capability/2` read the entities.

Whether the generated cheat sheet already lists this entity is UNKNOWN until
`mix spark.cheat_sheets` is re-run.

## Compile-time verification

`AshGraphLaw.Contract.validate/1` runs as the extension verifier and reports:

| Code | Condition |
|---|---|
| `:duplicate_admission` | two admissions share a `name` |
| `:missing_law_module` | a payload-bearing step has no `law` module |
| `:invalid_trusted_key` | a `trusted_keys` entry is not 64 hex characters |
| `:invalid_runtime_option` | `timeout_ms` is not above 0, or `max_skew_secs` is negative |
| `:duplicate_capability` | two `capability` entities share a `name` (raised by `Contract`; no `duplicate_capability` row exists in `ontology.ttl`, so it is not in the closed refusal table) |
| `:unknown_capability` | a `capability` name is not in `Registry.names/0`, or the registry module is unavailable |
| `:ceiling_unmet` | a `capability` ceiling is below the op's minimum |

## Reading the DSL

Application code reads admissions through `AshGraphLaw.Admissions` (`all/1`, `fetch/2`,
`runtime/1`), which returns structs or a typed `:unknown_admission` refusal. Standing is never
stored in the DSL; it is derived from a result (see
[authority boundary](../topics/authority_boundary.md)).

## See Also

- [ABI reference](abi_reference.md)
- [Typed refusals](typed_refusals.md) (generated)
- [DSL cheat sheet](../dsls/DSL-AshGraphLaw.Resource.md) (generated by Spark)
- [Claims and evidence](claims_and_evidence.md)
