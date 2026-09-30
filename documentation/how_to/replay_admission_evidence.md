<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Replay Admission Evidence

Recompute the digests bound to an admission and compare them with what was recorded.

## What is recorded

`AshGraphLaw.Evidence` carries `admission`, `standing`, `input_digest` (sha256 hex of the projected
N-Triples), `graph_ids`, `receipts`, `wasm_sha256`, `graphlaw_release`, `lease` identity, an
optional `origin` (`AshGraphLaw.Projection.Origin`) and `digest`.

## Recompute

```elixir
{:ok, %{text: text}} = MyProjection.data(changeset, [])
input_digest = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

input_digest == evidence.input_digest
AshGraphLaw.Evidence.digest(evidence) == evidence.digest
```

`Evidence.digest/1` hashes the canonical encoding (sorted keys) without the `:digest` field, so
identical evidence gives byte-identical digests. Evidence without an `origin` keeps its
pre-origin encoding and digest.

## Replay the engine step

Send the same `law` request to the same engine bytes and compare the `states`, `receipts` and
`nquads`. Compare `evidence.wasm_sha256` with `AshGraphLaw.WasmConfig.pinned_sha256/0` first: a
different engine is a different subject.

## Limits

A matching digest shows the same input produced the same record. It does not show the admission
was authorized, and `Standing.of/1` never returns `:ALIVE` for an admission result.

## See Also

- [Replayable admission evidence livebook](replayable_admission_evidence.livemd)
- [Authority boundary](../topics/authority_boundary.md)
- [Usage rule: evidence and standing](../../usage-rules/evidence-standing.md)
