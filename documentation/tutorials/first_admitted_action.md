<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# First Admitted Action

By the end you will have an Ash resource whose `:open` action is admitted by a SHACL shape run in
GraphLaw, an `AshGraphLaw.Evidence` value from an admitted call, and a typed refusal from a
rejected one. Complete [Getting Started](getting_started.md) first: the engine must be vendored
and the pool started. Outputs shown are what the code is designed to return; observed output is
UNKNOWN until the `:wasm` tests run them.

## 1. Write a law module

A law module supplies the graph data and the GraphLaw `law` steps. Here the law module builds the
data itself with `data/2`, so no assumption is made about the default projection's predicates.

```elixir
defmodule MyApp.TicketShapeLaw do
  @behaviour AshGraphLaw.Law

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix ex: <https://example.org/> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  ex:TicketShape a sh:NodeShape ;
    sh:targetClass ex:Ticket ;
    sh:property [ sh:path ex:title ; sh:datatype xsd:string ; sh:minCount 1 ] .
  """

  @impl true
  def data(changeset, _admission) do
    title = Ash.Changeset.get_attribute(changeset, :title)

    body =
      case title do
        nil -> "<urn:ticket:new> a ex:Ticket ."
        t -> "<urn:ticket:new> a ex:Ticket ; ex:title #{inspect(t)} ."
      end

    {:ok, %{text: "@prefix ex: <https://example.org/> .\n" <> body, dialect: "turtle"}}
  end

  @impl true
  def steps(_changeset, _admission), do: [%{"step" => "shacl", "shapes" => @shapes}]
end
```

## 2. Declare the admission and attach it

```elixir
defmodule MyApp.Ticket do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  graphlaw do
    runtime do
      timeout_ms 5000
    end

    admission :ticket_shape do
      step :shacl
      law MyApp.TicketShapeLaw
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]

    create :open do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
    end
  end
end
```

`MyApp.Domain` must list `MyApp.Ticket` as a resource. The default `ceiling` is `:construct`;
see [Declare an Admission](../how_to/declare_an_admission.md) for how a signed lease meets it. In
the `runtime` section, `trusted_keys` names the signers whose leases the engine may accept.

## 3. Observe Evidence

`:ceiling` defaults to `:construct`, so the caller supplies a signed lease (`signed` here is a
lease map signed by a key listed in `trusted_keys`, see
[Declare an Admission](../how_to/declare_an_admission.md)) through the changeset context under
`:graphlaw_lease`:

```elixir
{:ok, ticket} =
  MyApp.Ticket
  |> Ash.Changeset.for_create(:open, %{title: "Printer offline"},
    context: %{graphlaw_lease: %{signed_lease: signed}}
  )
  |> Ash.create()
```

On success `AshGraphLaw.Change.Admit` stores an `AshGraphLaw.Evidence` at
`changeset.context.graphlaw` during the action. `Ash.create/1` returns the record, not the
changeset, so read Evidence inside your own `after_action` hook, or call `AshGraphLaw.law/3`
directly. Evidence fields:
`:admission, :standing, :input_digest, :graph_ids, :receipts, :digest, :wasm_sha256,
:graphlaw_release, :lease` (the last is the identity of the presented signed lease: ceiling,
lease id, signer key id and lease digest). The standing of an admitted result is `:PARTIAL_ALIVE`: admission was
observed on the exact input and its consequence was not executed.

## 4. Observe a refusal

Omit the title. The shape requires `ex:title` with `sh:minCount 1`, so the engine refuses:

```elixir
{:error, error} =
  MyApp.Ticket
  |> Ash.Changeset.for_create(:open, %{}, context: %{graphlaw_lease: %{signed_lease: signed}})
  |> Ash.create()

[%AshGraphLaw.Refusal{code: code, class: class}] = AshGraphLaw.Error.refusals(error)
{code, class}
#=> {:not_admitted, :refused_admission}
```

Omit the lease and the ceiling check refuses before the engine runs:

```elixir
{:error, error} =
  MyApp.Ticket
  |> Ash.Changeset.for_create(:open, %{title: "Printer offline"})
  |> Ash.create()

AshGraphLaw.Error.codes(error)
#=> [:ceiling_unmet]
```

## See Also

- [Getting Started](getting_started.md)
- [Declare an Admission](../how_to/declare_an_admission.md)
- [Write a Law Module](../how_to/write_a_law_module.md)
- [Handle Refusals](../how_to/handle_refusals.md)
- [Claims and Evidence](../reference/claims_and_evidence.md)
