<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Actions and Atomics

- Admission needs a WASM call. `Change.Admit.atomic/3` returns
  `{:not_atomic, "GraphLaw admission requires a WASM call"}`; `Change.Canonicalize.atomic/3`
  returns `{:not_atomic, "GraphLaw canonicalization requires a WASM call"}`.
- Set `require_atomic? false` on any action that attaches a GraphLaw change.
- `Ash.bulk_update/4` with `strategy: :atomic` is refused by Ash; use `strategy: :stream`.
- Engine-backed calculations (`Conforms`, `CanonicalId`, `Sparql`) define no `expression/2`; they
  cost one engine call per record and cannot be pushed into a data layer.
- Attach admission with `change` (evidence in the changeset context), `validate` (pass or fail,
  no evidence) or `prepare` (reads and generic actions).
- A refused admission leaves no data-layer write.
- Do not build an atomic wrapper that skips the engine call.

Pinned by `test/ash/atomic_test.exs`. See
[use atomic actions](../documentation/how_to/use_atomic_actions.md).
