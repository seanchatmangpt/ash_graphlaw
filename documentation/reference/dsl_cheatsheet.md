<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# dsl_cheatsheet

One page. Full tables: [DSL reference](dsl_reference.md). Generated cheat sheet:
[DSL-AshGraphLaw.Resource.md](../dsls/DSL-AshGraphLaw.Resource.md); it wins on any disagreement.

```elixir
use Ash.Resource, domain: MyApp.Domain, extensions: [AshGraphLaw.Resource]

graphlaw do
  runtime do
    timeout_ms 5_000              # > 0
    max_skew_secs 60              # >= 0
    trusted_keys ["<64 hex>"]     # only trust anchors
  end

  admission :ticket_shape do      # unique by name
    step :shacl                   # see steps
    ceiling :construct            # :observe | :select | :construct (default :construct)
    law MyApp.ShapeLaw            # AshGraphLaw.Law
    projection MyApp.Projection   # AshGraphLaw.Projection
  end

  capability :sparql do           # unique by name; name in Registry.names/0
    ceiling :observe              # default :observe
    doc "read-only queries"
  end
end
```

## Steps

`:shacl :n3 :rdfs :owl_rl :hooks :plan :require_receipt :require_signed_receipt`. `record-receipts`
is not an admission step.

## Op ceilings (minimum for a `capability`)

| Ceiling | Ops |
|---|---|
| `:observe` | `capabilities sniff parse convert canonical sparql shacl shex policy` |
| `:construct` | `n3 entail datalog hooks law` |

## Attach to actions

```elixir
change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
validate {AshGraphLaw.Validation.Admissible, admission: :ticket_shape}
prepare {AshGraphLaw.Preparation.Admit, admission: :ticket_scope}
validate {AshGraphLaw.Validation.Shacl, shapes: @shapes}
change {AshGraphLaw.Change.Canonicalize, attribute: :graph_id}
calculate :valid?, :boolean, {AshGraphLaw.Calculation.Conforms, shapes: @shapes}
```

## Verifier refusals

`:duplicate_admission`, `:missing_law_module`, `:invalid_trusted_key`, `:invalid_runtime_option`,
plus for `capability`: `:duplicate_capability`, `:unknown_capability` (name not in the registry)
and `:ceiling_unmet` (ceiling below the op's minimum), as named in `lib/ash_graphlaw/contract.ex`.

## Read

`AshGraphLaw.Admissions.all/1`, `fetch/2`, `runtime/1`, `capabilities/1`, `capability/2`.
Never the generated `Info` from hand-written code.
