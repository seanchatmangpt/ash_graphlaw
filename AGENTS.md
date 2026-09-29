<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# AshGraphLaw Agent Operating Contract

Live tree evidence outranks stale prose. A deeper `AGENTS.md` may tighten this contract but
not weaken evidence, authority, replay, or generation law.

## Product invariant

AshGraphLaw hosts the pinned GraphLaw WASM engine (release `v26.9.28`, ABI version 1) inside
an Ash extension. The caller proposes; GraphLaw derives and validates; the library
transports and projects a typed success or typed refusal. GraphLaw never authorizes, and
nothing in this library grants authority. Admission evidence is an observation bound to an
exact input digest.

It is not a data layer, triplestore, policy engine, or authorization system.

## Preserve -> Fence -> Calculus

- Preserve: public DSL, refusal code table, ABI shape, generated/hand ownership, digest pin.
- Fence: read the origin of a boundary before removing it (Chesterton). One failed edge is
  topology, not graph failure.
- Calculus: `A = mu(O*)`, `R = receipt(A)`. Separate SELECT, CONSTRUCT, DO. Model, planner,
  generator, hook and proof output carry no execution authority.

## Evidence and standing

Vocabulary: `UNKNOWN | PARTIAL_ALIVE | ALIVE | BLOCKED | BUILD_BROKEN | UNSUPPORTED`, plus a
typed `%AshGraphLaw.Refusal{}` (`code`, `class`, `broken_term`).

- `{:ok, %Admitted{}}` derives `PARTIAL_ALIVE`: admission observed, consequence not executed.
  `ALIVE` needs observed execution against the exact admitted subject.
- `blocked_resource` refusals derive `BLOCKED`; `unsupported` derives `UNSUPPORTED`; other
  refusals derive `UNKNOWN`. Standing is derived, never stored.
- Inspection is not execution; compile success is not an admission; a workflow is not a run.

## Generation law

Generated, never hand-edited: `lib/ash_graphlaw/{resource,persist,verify,info,abi,receipt,
admitted,standing,refusal}.ex`, `lib/ash_graphlaw.ex`, `lib/mix/tasks/ash_graphlaw.install.ex`,
`mix.exs`, `.formatter.exs`, `.gitignore`, `README.md`, `LICENSE`,
`priv/graphlaw/MANIFEST.json`, `test/test_helper.exs`,
`test/ash_graphlaw_composition_test.exs`, `documentation/reference/typed_refusals.md`,
and (via `mix spark.cheat_sheets`) `documentation/dsls/DSL-AshGraphLaw.Resource.md`.

Sources: `ontology.ttl`, `queries/`, `gates/`, `templates/`, `ggen.toml`. Edit sources, run
`scripts/ggen_sync.sh` (after `scripts/vendor_marketplace.sh`), verify. Hand-written residue
(Host, Pool, EngineLoad, WasmConfig, Application, Admissions, Authority, Contract, Law, Projection, Evidence, Error, Change, Validation,
Preparation, Mutation, Mix tasks vendor/verify/mutate, tests, prose docs) is labeled
`UNSUPPORTED(generator-capability)`. Hand code never calls generated `Info`; it uses
`AshGraphLaw.Admissions`.

## Work and verification ladder

```text
mix format --check-formatted
-> mix compile --warnings-as-errors
-> mix credo --strict
-> mix dialyzer
-> mix test (unit)
-> mix test (ash)
-> mix test (negative, adversarial)
-> mix test (integration, :wasm)
-> mix ash_graphlaw.mutate --require-killed
-> mix hex.build
```

Cheapest high-information step first. Preserve and classify a failure (session-introduced or
pre-existing), form a hypothesis, repair at the source, rerun the failed boundary, then
expand. Tests are Chicago style: real collaborators, no mocks, positive control before each
negative. CI supplements local execution; it is not truth. Report exact commands and exit
codes; never claim unrun work.

## No branches, main only

Work on `main` in the one canonical checkout. No branches, worktrees, clones or copies
(the gitignored `vendor/` archive extract is the only scratch). Never rebase or force push.
Agent lanes do not run git state commands; the coordinator commits.

## Concrete reference

### DSL example

```elixir
defmodule MyApp.Ticket do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  graphlaw do
    runtime do
      timeout_ms 5_000
    end

    admission :ticket_shape do
      step :shacl
      law MyApp.ShapeLaw
    end
  end

  actions do
    create :open do
      change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
    end
  end
end
```

### Change usage

```elixir
case Ash.create(MyApp.Ticket, %{title: "x"}, action: :open) do
  {:ok, ticket} -> ticket
  {:error, error} -> error   # wraps AshGraphLaw.Error.Refused carrying %Refusal{}
end
```

On success the changeset context holds `:graphlaw` evidence. Its exact propagation to the
returned record is UNKNOWN until the integration tests run.

### Config

`config :ash_graphlaw, start_pool: true`, `config :ash_graphlaw, wasm_path: "..."`,
`GRAPHLAW_WASM_PATH`. The `.wasm` is fetched by `mix ash_graphlaw.vendor` and pinned by
sha256.

## See Also

[usage-rules.md](usage-rules.md) - [usage-rules/](usage-rules/) -
[documentation/README.md](documentation/README.md)
