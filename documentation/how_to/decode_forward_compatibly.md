<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Decode Forward-Compatibly

Read engine answers so that a newer engine cannot break your code.

## Rules the generated result structs follow

- `AshGraphLaw.Result.<Op>.from_map/1` never raises. Missing, extra or mistyped keys are tolerated.
- `raw` holds the entire decoded response map, including `"ok"` and any key this version does not
  know. `from_map(m).raw == m` for every map `m`.
- A field whose value does not match its registry type keeps the raw value untouched.
- Enum-like values (`dialect`, `engine`, `severity`) stay open strings.
- Tagged ops set `kind`: for `sparql`, `:solutions`, `:graph`, `:boolean` or `{:unknown, tag}`.

## Match with a fallback

```elixir
case AshGraphLaw.Capability.API.sparql(data: data, query: query) do
  {:ok, %{kind: :solutions, rows: rows}} -> rows
  {:ok, %{kind: :graph, nquads: nq}} -> nq
  {:ok, %{kind: :boolean, value: v}} -> v
  {:ok, %{kind: {:unknown, tag}, raw: raw}} -> {:unhandled_kind, tag, raw}
  {:error, %AshGraphLaw.Refusal{} = refusal} -> {:refused, refusal.code}
end
```

## Read a field the struct does not have

```elixir
{:ok, result} = AshGraphLaw.Capability.API.canonical(data: text)
result.raw["a_field_added_by_a_newer_engine"]
```

## Refusals

`AshGraphLaw.Refusal.from_engine/2` maps an unknown engine `kind` to `:engine_unclassified` (class
`:unsupported`) and keeps the whole engine error in `refusal.raw`. Match on `code`, never on
message text.

## Terms

`AshGraphLaw.Result.Term` has `type`, `value`, `datatype`, `lang` (from `"xml:lang"`) and `raw`.
Every other nested object stays a plain string-keyed map.

## See Also

- [Use typed capabilities](use_typed_capabilities.md)
- [Handle refusals](handle_refusals.md)
- [ABI reference](../reference/abi_reference.md)
