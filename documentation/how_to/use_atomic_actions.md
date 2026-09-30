<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Use Atomic Actions

Admission needs a WASM call, so it cannot be an atomic update.

## Behavior

`AshGraphLaw.Change.Admit.atomic/3` returns
`{:not_atomic, "GraphLaw admission requires a WASM call"}`. `AshGraphLaw.Change.Canonicalize`
returns `{:not_atomic, "GraphLaw canonicalization requires a WASM call"}`. Calculations that call
the engine (`Conforms`, `CanonicalId`, `Sparql`) define no `expression/2`.

## Consequences

| Call | Result |
|---|---|
| `Ash.update/3` on an action with `require_atomic?: true` | refused by Ash with the reason above |
| `Ash.bulk_update/4` with `strategy: :atomic` | refused by Ash with the reason above |
| `Ash.bulk_update/4` with `strategy: :stream` | runs the change per record |

Set `require_atomic? false` on the action that carries an admission:

```elixir
update :close do
  require_atomic? false
  change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
end
```

Pinned by `test/ash/atomic_test.exs`.

## See Also

- [Declare an admission](declare_an_admission.md)
- [Usage rule: actions and atomics](../../usage-rules/actions-and-atomics.md)
