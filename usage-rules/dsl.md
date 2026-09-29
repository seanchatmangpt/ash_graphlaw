<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Dsl

The extension adds one section, `graphlaw`, to an Ash resource. It is generated from the
ash-extension-pack spec in `ontology.ttl`; change the ontology, not `resource.ex`.

## Shape

```elixir
graphlaw do
  runtime do
    timeout_ms 5_000
  end

  admission :ticket_shape do
    step :shacl
    law MyApp.ShapeLaw
  end

  admission :ticket_close do
    step :plan
    ceiling :select
    law MyApp.PlanLaw
  end
end
```

## Entities

| Entity | Struct | Fields |
|---|---|---|
| `runtime` (singleton) | `AshGraphLaw.Dsl.Runtime` | `wasm_path` (nil), `timeout_ms` (5000), `max_skew_secs` (60), `trusted_keys` ([]) |
| `admission` (arg `:name`) | `AshGraphLaw.Dsl.Admission` | `name` (required), `step` (required), `ceiling` (`:construct`), `law` (nil), `projection` (nil) |

`step` is one of `:shacl :n3 :rdfs :owl_rl :hooks :plan :require_receipt
:require_signed_receipt`. `ceiling` is one of `:observe :select :construct`.

## Rules

- Do declare at most one `runtime` entity; omit it to take struct defaults.
- Do give every `admission` a unique `name`. A duplicate is `:duplicate_admission`.
- Do supply a `law` module for `:shacl :n3 :hooks :plan :require_receipt
  :require_signed_receipt`. Only `:rdfs` and `:owl_rl` may omit it
  (`:missing_law_module` otherwise).
- Do write `trusted_keys` as 64-character hex strings (`:invalid_trusted_key`).
- Do keep `timeout_ms > 0` and `max_skew_secs >= 0` (`:invalid_runtime_option`).
- Do not put standing on the DSL. Standing is derived from results, never stored.
- Do not put authority on the DSL. `ceiling` is a limit the caller's lease must meet, not a
  grant.
- Do not read the DSL from hand-written code with generated `Info`; use
  `AshGraphLaw.Admissions.all/1`, `fetch/2`, `runtime/1`.

Compile-time violations are reported by the generated verifier, which delegates to
`AshGraphLaw.Contract.validate/1`.

## See Also

[admission.md](admission.md) - [refusals.md](refusals.md) - [../usage-rules.md](../usage-rules.md)
