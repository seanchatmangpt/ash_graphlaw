<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Use the Reactor Hooks Step

Run a GraphLaw knowledge-hook pack, or any op, as a Reactor step.

## Prerequisite

`reactor` is an optional dependency. Add it to your project:

```elixir
{:reactor, "~> 0.15"}
```

The step modules compile either way. Without Reactor they define an inert `run/3` that returns
`{:error, "Reactor library is not loaded"}`. `AshGraphLaw.Reactor.available?/0` reports which.
The version constraint above is an assumption to check against your Reactor version.

## Hooks

```elixir
defmodule MyApp.FireHooks do
  use Reactor

  input :pack
  input :data

  step :fire, AshGraphLaw.Reactor.Hooks do
    argument :pack, input(:pack)
    argument :data, input(:data)
  end

  return :fire
end

Reactor.run(MyApp.FireHooks, %{pack: pack_ttl, data: data_ttl})
```

Result: `{:ok, %AshGraphLaw.Result.Hooks{}}` (`id`, `rounds`, `quads`, `nquads`, `firings`) or an
error carrying `%AshGraphLaw.Refusal{}`.

## Any op

```elixir
step :shapes, AshGraphLaw.Reactor.Capability, op: "shacl" do
  argument :data, input(:data)
  argument :shapes, input(:shapes)
end
```

`op:` is validated when the step runs; a name outside `Registry.names/0` is `:unknown_capability`.
Other options (`:server`, `:timeout`) are forwarded to the engine call.

## Compensation and retry

The steps define no `compensate/4` or `undo/4`: hooks derive quads and record firings, nothing is
actuated. A refusal is a typed answer, so the steps never ask Reactor to retry. A hook firing is an
observation, never authority.

## Status

The step modules exist in `lib/ash_graphlaw/reactor/`. `test/integration/reactor_capability_test.exs`
exercises them; whether it passes is UNKNOWN until run with Reactor and the engine present.

## See Also

- [Use typed capabilities](use_typed_capabilities.md)
- [Support matrix](../reference/support_matrix.md)
