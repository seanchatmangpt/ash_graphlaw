<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# How to: Declare Admissions and Wire Them to Actions

A focused recipe for declaring GraphLaw admissions on an Ash resource and attaching them to
actions, validations and preparations. The tutorial
([first admission](../tutorials/first-admission.md)) runs one end to end; this page is the
working reference for the wiring itself.

## Declare admissions

Use the `AshGraphLaw.Resource` Spark extension and a `graphlaw` section:

```elixir
defmodule Ticket do
  use Ash.Resource,
    domain: MyDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  graphlaw do
    admission(:ticket_shape, step: :shacl, ceiling: :observe)
    admission(:ticket_close, step: :plan, ceiling: :select, law: TicketLaw)
  end
end
```

Each `admission/2` entry accepts:

- `:name` (required atom, unique per resource)
- `:step` (required; one of `:shacl, :n3, :rdfs, :owl_rl, :hooks, :plan, :require_receipt,
  :require_signed_receipt`)
- `:ceiling` (`:observe`, `:select` or `:construct`; default `:construct`)
- `:law` (optional module implementing the `AshGraphLaw.Law` behaviour)
- `:projection` (optional module implementing `AshGraphLaw.Projection`; nil uses
  `AshGraphLaw.Projection.Default`)

All options verified against the `@admission` entity schema in
`/Users/sac/ash_graphlaw/lib/ash_graphlaw/resource.ex`.

## Set runtime options

```elixir
  graphlaw do
    runtime do
      timeout_ms(7000)
      max_skew_secs(60)
      trusted_keys([...])
    end
  end
```

Verified options in the `@runtime` entity schema (`lib/ash_graphlaw/resource.ex`): `wasm_path`,
`timeout_ms` (default `5000`, must be positive), `max_skew_secs` (default `60`), `trusted_keys`
(hex-encoded 32-byte public keys, 64 characters each) whose lease signatures the engine may
accept.

## Attach an admission to a create/update/destroy action

```elixir
  actions do
    create :open do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
    end

    update :close do
      accept []
      change {AshGraphLaw.Change.Admit, admission: :ticket_close, phase: :before_transaction}
    end

    destroy :cancel do
      change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
    end
  end
```

`AshGraphLaw.Change.Admit` (`lib/ash_graphlaw/change/admit.ex`) applies to `:create`, `:update`
and `:destroy` action types only; on others (for example `:read`) it returns the changeset
untouched. Full option table in the module doc:

| Option | Type | Default |
|---|---|---|
| `:admission` | atom (required) | none |
| `:projection` | module or nil | admission's, then `AshGraphLaw.Projection.Default` |
| `:server` | atom | `AshGraphLaw.Pool` |
| `:timeout` | positive integer (ms) | runtime section's `timeout_ms` |
| `:phase` | `:before_action` or `:before_transaction` | `:before_action` |
| `:lease_key` | atom | `:graphlaw_lease` |

## Gate reads with a preparation

```elixir
  actions do
    read :open_tickets do
      prepare {AshGraphLaw.Preparation.Admit, admission: :ticket_shape}
    end
  end
```

`AshGraphLaw.Preparation.Admit` (`lib/ash_graphlaw/preparation/admit.ex`) runs the declared
admission at prepare time; there is no `:phase` option. It refuses with `:unknown_admission`,
`:ceiling_unmet`, `:projection_failed` and related codes; never call it inside a data-layer
expression, because the admission needs a real engine call.

## Pass/fail validation without recorded evidence

```elixir
  validations do
    validate {AshGraphLaw.Validation.Admissible, admission: :ticket_shape}
  end
```

`AshGraphLaw.Validation.Admissible` (`lib/ash_graphlaw/validation/admissible.ex`) supports
`Ash.Changeset` and `Ash.ActionInput`; it records no evidence — use the change when evidence
matters.

## Supply the lease

The change reads the lease from `changeset.context[lease_key]` (default `:graphlaw_lease`):

```elixir
Ash.Changeset.for_create(Ticket, :open, %{title: "..."},
  context: %{graphlaw_lease: lease}
)
```

Only a `:signed_lease` entry (`%{"lease" => ..., "attestation" => ...}`) can raise the ceiling
above `:observe`; a bare ceiling atom or an unsigned map grants only `:observe`. Trust anchors,
skew and the clock are never taken from changeset context. See `lib/ash_graphlaw/authority.ex`
(`check_ceiling/2`, `op_ceiling/1`, `check_op/3`).

## Write a law module when the step needs a payload

Steps that need a payload (`AshGraphLaw.Contract.payload_steps/0`) require a law module
exporting `steps/2`; a raise inside it becomes the typed `:law_module_failed` refusal:

```elixir
defmodule TicketLaw do
  @behaviour AshGraphLaw.Law

  @impl true
  def steps(_subject, _admission), do: []

  # Optional: override the projected graph for this admission.
  # @impl true
  # def data(_subject, _admission), do: :default
end
```

Callbacks verified in `lib/ash_graphlaw/law.ex`: required `steps/2`
(`[map()]` with string keys), optional `data/2` returning `{:ok, %{text: text, dialect: dialect}}`
or `:default`. The inline fixture `AshGraphLaw.Compat.DslFixtures.AnyLaw` in
`/Users/sac/ash_graphlaw/test/compat/admission_dsl_compat_test.exs` is a real compiling example.

## Check what a resource declared

```elixir
AshGraphLaw.Admissions.all(Ticket)
AshGraphLaw.Admissions.fetch(Ticket, :ticket_shape)
AshGraphLaw.Admissions.declared?(Ticket, :ticket_shape)
```

Functions verified in `lib/ash_graphlaw/admissions.ex`: `all/1`, `fetch/2`, `runtime/1`,
`capabilities/1`, `capability/2`, `declared?/2`.

## Troubleshooting

- **`:unknown_admission`** — the `:admission` name does not match a declared admission on the
  resource. List them with `AshGraphLaw.Admissions.all/1`.
- **`:ceiling_unmet`** — the admission's `:ceiling` exceeds what the lease in changeset context
  supports; a missing lease gives `:observe` only. The refusal is raised before the engine is
  called (`lib/ash_graphlaw/change/admit.ex`, "Flow" section).
- **`:law_module_failed`** — the declared admission's law module raised in `steps/2`.
- **`:host_not_started`** (`:blocked_resource`) — the pool is not running or the engine is not
  vendored; run `mix ash_graphlaw.vendor` and set `config :ash_graphlaw, start_pool: true`.
