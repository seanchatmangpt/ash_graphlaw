<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Write a Law Module

Implement `AshGraphLaw.Law` to supply the `law` op steps (and optionally the graph data) for an
admission.

## The behaviour

```elixir
@callback steps(subject, admission) :: [map]
@callback data(subject, admission) :: {:ok, %{text: String.t(), dialect: String.t()}} | :default
```

`data/2` is optional. `:default` (or omitting it) uses the admission's projection, which is
`AshGraphLaw.Projection.Default` unless the admission sets `projection`.

## Steps use string keys

Formats come from the GraphLaw ABI tests. SHACL:

```elixir
def steps(_subject, _admission) do
  [%{"step" => "shacl", "shapes" => "@prefix sh: <http://www.w3.org/ns/shacl#> . ..."}]
end
```

Plan (actions with `pre`, `add`, `del` as N-Triples text, and a `goal`):

```elixir
def steps(_subject, _admission) do
  at = fn o -> "<urn:p:robot> <urn:p:at> <urn:p:#{o}> .\n" end

  [
    %{
      "step" => "plan",
      "plan" => %{
        "actions" => [%{"name" => "a-b", "pre" => at.("a"), "add" => at.("b"), "del" => at.("a")}],
        "goal" => at.("b")
      }
    }
  ]
end
```

Match the admission's `step` to the step you emit. Other step names (`n3` with `rules`, `rdfs`)
are shown in `/Users/sac/graphlaw/tests/wasm_abi.rs`; the authoritative refusal text is in
`/Users/sac/graphlaw/docs/refusals.md`.

## Supply your own data

```elixir
def data(changeset, _admission) do
  {:ok, %{text: "<urn:t:1> <urn:p:state> \"open\" .\n", dialect: "ntriples"}}
end
```

The digest recorded in Evidence is the SHA-256 of this text, so the same input yields the same
`input_digest`.

## Rules

- A law module returns steps; it never grants authority.
- Raising or returning a non-list surfaces as `:law_module_failed` (UNKNOWN until a test
  demonstrates the exact path).
- Steps that need a payload require `law` on the admission (`:missing_law_module` otherwise).

## See Also

- [Declare an Admission](declare_an_admission.md)
- [Handle Refusals](handle_refusals.md)
- [ABI Reference](../reference/abi_reference.md)
