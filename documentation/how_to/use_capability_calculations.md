<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Use Capability Calculations

Expose engine answers as Ash calculations, validations and changes over a projected record.

All of these project the record through `AshGraphLaw.Projection` (default
`AshGraphLaw.Projection.Default`), call the typed op, and turn a refusal into
`AshGraphLaw.Error.Refused`. None implements RDF semantics.

## Conformance

```elixir
calculations do
  calculate :valid?, :boolean, {AshGraphLaw.Calculation.Conforms, shapes: @shapes}
end
```

Returns the engine's `shacl.conforms`.

## Canonical identity

```elixir
calculations do
  calculate :graph_id, :string, AshGraphLaw.Calculation.CanonicalId
end
```

Returns `"sha256:..."` from the `canonical` op. The default projection puts the primary key in the
subject IRI, so use a projection without it when the id must depend on attribute values only.

## SPARQL

```elixir
calculations do
  calculate :titles, {:array, :map},
    {AshGraphLaw.Calculation.Sparql, query: "SELECT ?t WHERE { ?s ?p ?t }", terms: :values}
end
```

Value by result kind: solutions give a list of `%{variable => value}`, a graph gives N-Quads text,
a boolean gives the ASK answer. `terms: :raw` keeps the engine term.

## Validation and change

```elixir
validations do
  validate {AshGraphLaw.Validation.Shacl, shapes: @shapes}
end

actions do
  create :create do
    accept [:title]
    change {AshGraphLaw.Change.Canonicalize, attribute: :graph_id}
  end
end
```

`Validation.Shacl` fails with `AshGraphLaw.Validation.Shacl.NonConformance` (the engine's results)
when the graph does not conform, and with `AshGraphLaw.Error.Refused` when the call is refused.
`Change.Canonicalize` writes the id in `before_action` and is not atomic.

## Shared options

`:projection`, `:server`, `:timeout`, `:lease`, and for changeset modules `:lease_key` (default
`:graphlaw_lease`). Trust anchors and clocks are never read from options.

## Declared capabilities

If the resource declares `capability` entities, the op must be among them
(`:capability_not_declared` otherwise), and a presented `:lease` must meet the declared ceiling.

## Cost

Each record is one engine round trip. Calculations define no `expression/2` and cannot be pushed
into a data layer.

## See Also

- [Use typed capabilities](use_typed_capabilities.md)
- [Use atomic actions](use_atomic_actions.md)
- [Usage rule: lifecycle](../../usage-rules/lifecycle.md)
