<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Handle Refusals

Recover the typed `AshGraphLaw.Refusal` from an error returned by an Ash action.

## Recover from an Ash error

Ash aggregates action errors into a class such as `Ash.Error.Invalid`. The refusal survives
inside it:

```elixir
case Ash.create(changeset) do
  {:ok, record} ->
    {:ok, record}

  {:error, error} ->
    case AshGraphLaw.Error.refusals(error) do
      [%AshGraphLaw.Refusal{code: code, class: class, broken_term: term} | _] ->
        {:refused, code, class, term}

      [] ->
        {:error, error}
    end
end
```

Helpers: `AshGraphLaw.Error.refusals/1` (all refusals), `codes/1` (codes only), `refused?/1`.
They accept a bare `AshGraphLaw.Error.Refused`, a bare `Refusal`, an error class, or a list.

## Branch on class

`class` is one of `:refused_identity`, `:refused_structure`, `:refused_authority`,
`:refused_admission`, `:blocked_resource`, `:unsupported`.

```elixir
case refusal.class do
  :blocked_resource -> :retry_later
  :refused_admission -> :reject_input
  :refused_authority -> :request_lease
  _ -> :investigate
end
```

## Derive standing

```elixir
AshGraphLaw.Standing.of({:error, refusal})
```

A `:blocked_resource` refusal gives `:BLOCKED`, `:unsupported` gives `:UNSUPPORTED`, any other
refusal gives `:UNKNOWN`. Typed REFUSED is carried by the `Refusal`, not by standing.

## Direct calls

`AshGraphLaw.call/2` and `AshGraphLaw.law/3` return `{:error, %AshGraphLaw.Refusal{}}` directly;
no unwrapping is needed.

## See Also

- [Typed Refusals](../reference/typed_refusals.md)
- [Declare an Admission](declare_an_admission.md)
- [First Admitted Action](../tutorials/first_admitted_action.md)
