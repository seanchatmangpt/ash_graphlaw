<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Test Resources That Use Admissions

Chicago style: real Ash resources, a real host, the real pinned engine. No mocks.

## Setup

```bash
mix ash_graphlaw.vendor       # fetch and digest-check the engine
mix test                      # :wasm tests run when the engine is vendored
```

`test/test_helper.exs` excludes `:wasm` tests with a printed reason when the engine is absent. An
excluded test contributes nothing to standing.

## Positive control first

```elixir
@moduletag :wasm

test "conforming subject is admitted" do
  assert {:ok, ticket} = Ash.create(MyApp.Ticket, %{title: "x"}, action: :open)
  assert ticket.title == "x"
end

test "violating subject is refused and writes nothing" do
  assert {:error, error} = Ash.create(MyApp.Ticket, %{title: ""}, action: :open)
  assert [:not_admitted] == AshGraphLaw.Error.codes(error)
  assert [] == Ash.read!(MyApp.Ticket)
end
```

A refusal test that has no passing sibling can pass vacuously.

## What to avoid

- No `Mox`, `Mimic`, `meck`, `patch`. Under `test/`, the repository greps for these.
- Assert on final state and refusal fields (`code`, `class`, `broken_term`), not on message text.
- Host behavior at ABI edges (trap, slow init, oversized response) uses
  `AshGraphLaw.Test.WasmFixtures.scripted_engine/1`, a real spec-valid module run by Wasmtime.

## See Also

- [Usage rule: testing](../../usage-rules/testing.md)
- [Run the mutation catalog](run_the_mutation_catalog.md)
