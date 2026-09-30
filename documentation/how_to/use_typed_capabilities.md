<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Use Typed Capabilities

Call any GraphLaw op with typed arguments and a typed result, without `AshGraphLaw.call/2`.

The modules named here are generated from the capability registry. Their per-op reference is
[capabilities.md](../reference/capabilities.md) (generated).

## Call an op

```elixir
{:ok, result} =
  AshGraphLaw.Capability.API.sparql(
    data: "@prefix ex: <https://e/> . ex:s ex:p 1 .",
    query: "SELECT ?o WHERE { <https://e/s> <https://e/p> ?o }"
  )

result.kind      #=> :solutions
result.variables #=> ["o"]
result.rows      #=> [[%AshGraphLaw.Result.Term{...}]]
```

Every op has `AshGraphLaw.Capability.API.<op>/2` and `<op>!/2`. `parse`, `convert`, `canonical`,
`sparql`, `shacl`, `shex`, `n3`, `entail`, `datalog` and `policy` are also delegated from the root
module (`AshGraphLaw.sparql/2`). `capabilities`, `sniff`, `law` and `hooks` keep their original
root functions and return shapes; their typed forms live on `AshGraphLaw.Capability.API`.

Arguments are a keyword list or a map. Keys are snake_case registry field names, atoms or strings.
A bare binary for a `data_spec` field means `%{"text" => binary}`.

## Options

The second argument is the same options list as `AshGraphLaw.call/2` (`:server`, `:timeout`,
`:fuel`). Lease fields are ordinary request arguments; typed ops do not read auth options.

## Errors

```elixir
{:error, %AshGraphLaw.Refusal{code: :invalid_capability_request, details: details}} =
  AshGraphLaw.Capability.API.shacl(data: "x")

details["missing"]  #=> ["shapes"]
```

| Condition | Code | Details |
|---|---|---|
| unknown key | `:invalid_capability_request` | `"unknown_keys"` |
| missing required field | `:invalid_capability_request` | `"missing"` |
| type mismatch | `:invalid_capability_request` | `"type_errors"` |
| unknown op name in `API.run/3` | `:unknown_capability` | |
| engine refusal | table code such as `:not_admitted` | `raw` holds the engine error |
| response not a JSON object | `:capability_response_undecodable` | |

`enum` values in the registry are informational and never enforced client-side: the engine decides.
The bang form raises `AshGraphLaw.Error.Refused`.

## Declare which ops a resource may run

```elixir
graphlaw do
  capability :shacl
  capability :sparql, ceiling: :observe
end
```

A resource that declares at least one capability refuses undeclared ops in the lifecycle modules
with `:capability_not_declared`. A resource that declares none allows all. See
[DSL reference](../reference/dsl_reference.md).

## Discover

```elixir
AshGraphLaw.Capability.Registry.names()
AshGraphLaw.Capability.Registry.op("shacl")
AshGraphLaw.Capability.Registry.module_for("shacl")
```

## See Also

- [Decode forward-compatibly](decode_forward_compatibly.md)
- [Use capability calculations](use_capability_calculations.md)
- [Capability registry and parity](../topics/capability_registry_and_parity.md)
- [Usage rule: capabilities](../../usage-rules/capabilities.md)
