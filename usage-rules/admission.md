<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Admission

## Attach an admission to an action

```elixir
create :open do
  change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
end
```

`AshGraphLaw.Change.Admit` options: `admission` (required atom), `projection` (module or
nil), `server`, `timeout`, `phase` (`:before_action` default, or `:before_transaction`),
`lease_key` (default `:graphlaw_lease`). Supported on create, update and destroy.

Flow: fetch the admission, check `ceiling` against the SIGNED lease in `changeset.context[lease_key]`
(`%{signed_lease: %{"lease" => ..., "attestation" => ...}}`; a bare atom grants only `:observe`), project,
compute `input_digest`, call `Law.steps/2`, call `AshGraphLaw.law/3`, then either set
`changeset.context.graphlaw` to an `%AshGraphLaw.Evidence{}` or add an
`AshGraphLaw.Error.Refused` error.

## Rules

- Do expect `ceiling_unmet` before the engine is called when the signed lease is below the ceiling
  or absent. Never pass a ceiling atom: it grants nothing. The signer must be in `runtime trusted_keys`.
- Do read evidence from `changeset.context[:graphlaw]`; it carries `admission`, `standing`,
  `input_digest`, `graph_ids`, `receipts`, `digest`, `wasm_sha256`, `graphlaw_release`, `lease`
  (the presented lease identity).
- Do not use evidence as authorization. It is an observation bound to an input digest.
- Do not assume atomic actions. `atomic/3` returns `{:not_atomic, ...}` because a WASM call
  is required.
- Use `AshGraphLaw.Validation.Admissible` for pass/fail only (no evidence). Use
  `AshGraphLaw.Preparation.Admit` for `Ash.Query` and `Ash.ActionInput`.
- Refusal reaches Ash as `AshGraphLaw.Error.Refused` (class `:invalid`) carrying the
  `%Refusal{}`; `code` and `broken_term` survive `Ash.Error.to_error_class/1`.

## Law modules

```elixir
defmodule MyApp.ShapeLaw do
  @behaviour AshGraphLaw.Law
  def steps(subject, admission), do: [...]   # string-key maps in the GraphLaw `law` format
  def data(_subject, _admission), do: :default
end
```

- Do take the step format from `/Users/sac/graphlaw/tests/wasm_abi.rs` and
  `docs/refusals.md`, not from memory.
- Do return `{:ok, %{text: text, dialect: dialect}}` from `data/2` only to override the
  projection; `:default` uses it.
- A raising law module becomes `:law_module_failed`; a failing projection becomes
  `:projection_failed`.

## Projection

`AshGraphLaw.Projection.Default` emits deterministic sorted N-Triples (dialect
`"ntriples"`) with subject `<urn:ash-graphlaw:resource:{Module}:{pk-or-new}>`. Same input
gives byte-identical output. `input_digest` is sha256 of that text.

## Direct calls

`AshGraphLaw.law(data, steps, opts)` returns `{:ok, %Admitted{}}` or `{:error, %Refusal{}}`.
Opts keys: `:server :timeout :signed_lease :trusted_keys :max_skew_secs :lease
:unverified_lease :now_unix`. Request maps use string keys. These options belong to the raw
`AshGraphLaw.law/3` call; the Ash change and validation take authority only from a signed lease in
context and from `runtime` (`AshGraphLaw.Authority`), never from caller-supplied trust anchors.

## Telemetry

`[:ash_graphlaw, :admission, :stop]` with `%{duration}` and metadata `admission`, `outcome`,
`code`, `standing`.

## See Also

[dsl.md](dsl.md) - [refusals.md](refusals.md) - [../usage-rules.md](../usage-rules.md)
