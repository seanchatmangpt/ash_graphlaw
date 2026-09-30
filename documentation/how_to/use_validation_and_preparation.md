<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Use Validation and Preparation

Admit through an Ash validation or a read/generic-action preparation instead of a change.

## Validation

```elixir
actions do
  create :open do
    validate {AshGraphLaw.Validation.Admissible, admission: :ticket_shape}
  end
end
```

`AshGraphLaw.Validation.Admissible` runs the same admission path as the change and reports
pass or fail. It produces no evidence and writes nothing into the changeset context.

## Preparation

```elixir
actions do
  read :list do
    prepare {AshGraphLaw.Preparation.Admit, admission: :ticket_shape}
  end
end
```

`AshGraphLaw.Preparation.Admit` applies to read queries and generic-action input.

## Behavior shared with the change

- Authority is checked before the engine (`:ceiling_unmet`).
- An unknown admission is `:unknown_admission`; no running host is `:host_not_started`.
- A refusal reaches Ash as `AshGraphLaw.Error.Refused` carrying the typed `%Refusal{}`.

Engine-backed paths are `:wasm` tests (`test/ash/validation_test.exs`, `test/ash/preparation_test.exs`);
their standing is UNKNOWN until run against the engine.

## See Also

- [Handle refusals](handle_refusals.md)
- [Use typed capabilities](use_typed_capabilities.md) (`AshGraphLaw.Validation.Shacl`)
- [Usage rule: admission](../../usage-rules/admission.md)
