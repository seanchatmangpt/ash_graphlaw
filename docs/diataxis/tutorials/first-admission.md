<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Tutorial: Your First Admission

Admission is the core loop of `ash_graphlaw`: a caller proposes a request, the pinned
`graphlaw.wasm` engine derives and validates it, and the library projects the outcome as either
a typed success (`AshGraphLaw.Admitted`) or a typed refusal (`AshGraphLaw.Refusal`). This
tutorial runs that loop once, end to end, on real bytes.

## What you will build

A single Ash resource with one declared GraphLaw admission and one create action gated by
`AshGraphLaw.Change.Admit`. By the end you will have:

- vendored and verified the pinned GraphLaw engine,
- declared an admission on a resource using the `AshGraphLaw.Resource` extension,
- run a create through the engine and observed a typed outcome.

## Prerequisites

- Elixir `~> 1.17` (see `mix.exs` in the `ash_graphlaw` repository, `@version 26.10.1`)
- Ash `~> 3.33 and >= 3.33.11`
- Network access the first time, to download the engine release asset

## 1. Add the dependency

```elixir
def deps do
  [
    {:ash, "~> 3.33 and >= 3.33.11"},
    {:ash_graphlaw, "~> 26.10.1"}
  ]
end
```

```bash
mix deps.get
```

The runtime dependency floor is recorded in `/Users/sac/ash_graphlaw/mix.exs` (`deps/0`, the
`{:ash, "~> 3.33 and >= 3.33.11"}` line); `wasmex ~> 0.15.1` arrives transitively and hosts the
WASI module.

## 2. Vendor and verify the engine

The engine binary is never shipped in the Hex package; the pin (release tag, URL, SHA-256) lives
in `priv/graphlaw/MANIFEST.json`. Fetch it and check it:

```bash
mix ash_graphlaw.vendor
mix ash_graphlaw.vendor --check
```

`--check` writes nothing and exits non-zero when the file is absent or its digest differs from
the pin. Then run one real call through the vendored bytes:

```bash
mix ash_graphlaw.verify
```

This applies the digest pin, the import allowlist and the required-export check, starts a real
host, sends `capabilities` and requires the reported `abi_version` to equal the manifest's. A
non-zero exit carries a typed refusal code.

## 3. Start the pool

The application starts no engine unless you ask. In `config/config.exs`:

```elixir
config :ash_graphlaw, start_pool: true
```

`AshGraphLaw.Application` then starts `AshGraphLaw.Pool` with size and timeout from
`config :ash_graphlaw, pool: [size: 4, timeout_ms: 5_000]` (see
`lib/ash_graphlaw/pool.ex` and `lib/ash_graphlaw/application.ex`).

## 4. Declare a resource with one admission

```elixir
defmodule Ticket do
  use Ash.Resource,
    domain: MyDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
  end

  actions do
    defaults [:read, create: []]
  end

  graphlaw do
    runtime do
      timeout_ms(7000)
    end

    admission(:ticket_shape, step: :shacl, ceiling: :observe)
  end
end
```

This is the exact DSL shape used by the compatibility fixtures in
`/Users/sac/ash_graphlaw/test/compat/admission_dsl_compat_test.exs`
(`AshGraphLaw.Compat.DslFixtures.AllSteps`): a `graphlaw` section containing a `runtime` block
(`timeout_ms/1` is a real option, verified in `lib/ash_graphlaw/resource.ex`, `@runtime` entity
schema) and `admission/2` entries. The `:admission` entity requires `:name` and `:step`; `:step`
is one of `:shacl, :n3, :rdfs, :owl_rl, :hooks, :plan, :require_receipt, :require_signed_receipt`
(`lib/ash_graphlaw/resource.ex`, `@admission` entity schema). `:ceiling` defaults to
`:construct`; `:law` and `:projection` are optional modules.

## 5. Wire the change onto an action

```elixir
  actions do
    create :open do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
    end
  end
```

`AshGraphLaw.Change.Admit` (`lib/ash_graphlaw/change/admit.ex`) applies to `:create`, `:update`
and `:destroy`; on any other action type it returns the changeset untouched. Its required option
is `:admission`, the name of a declared admission. The admission runs by default in
`:before_action` phase; pass `phase: :before_transaction` to move it earlier.

## 6. Run it

```bash
iex -S mix
```

```elixir
{:ok, caps} = AshGraphLaw.capabilities([])
caps["abi_version"]
#=> 1

AshGraphLaw.abi_version()
#=> 1
```

Both values must match; the first is read from the live engine, the second is compiled in from
the ontology (`lib/ash_graphlaw.ex`, `abi_version/0`). Then drive a real create:

```elixir
Ash.Changeset.for_create(Ticket, :open, %{title: "fix the membrane"}, context: %{graphlaw_lease: lease})
|> Ash.create()
```

The change reads the lease from `changeset.context[:graphlaw_lease]`
(`lib/ash_graphlaw/change/admit.ex`, "Lease context key" section). A bare ceiling atom or an
unsigned map grants only `:observe`; only a `:signed_lease` entry
(`%{"lease" => ..., "attestation" => ...}`) can raise the ceiling above `:observe`, and the
engine verifies its signature and expiry against the resource's `runtime.trusted_keys`. See
`lib/ash_graphlaw/authority.ex`.

## 7. Read the outcome

On success the engine returns receipts and the action proceeds. On refusal the action fails with
a typed `AshGraphLaw.Refusal` exception (`lib/ash_graphlaw/refusal.ex`): a closed `code`, a
`class` (one of `:refused_admission, :refused_authority, :blocked_resource, :refused_structure,
:unsupported, :refused_identity`), a `broken_term` from the Chatman failure taxonomy, engine
provenance and `details`. Provoke one by pointing at a nonexistent host:

```elixir
{:error, %AshGraphLaw.Refusal{code: code, class: class}} =
  AshGraphLaw.capabilities(server: :no_such_host)

{code, class}
#=> {:host_not_started, :blocked_resource}
```

That pairing is verified in `documentation/tutorials/getting_started.md` and
`lib/ash_graphlaw/refusal.ex` (`class_of(:host_not_started)`).

## Where next

- [How to declare admissions and wire them to actions](../how-to/declare-and-wire-admissions.md)
- [DSL and core API reference](../reference/dsl-and-core-api.md)
- [Why admission never grants authority](../explanation/admission-authority-standing.md)
