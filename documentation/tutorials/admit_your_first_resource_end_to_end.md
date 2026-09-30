<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Admit Your First Resource End to End

By the end you will have a small Mix application in which a `Ticket` resource:

- refuses to be opened unless a SHACL shape admits its projected data,
- requires a signed lease before it will call the engine at all,
- yields an `AshGraphLaw.Evidence` value you can store and replay,
- reports every failure as a typed `AshGraphLaw.Refusal`,
- and is covered by a Chicago-style ExUnit test with a real pool and no mocks.

Prerequisites: [Getting Started](getting_started.md) is done (engine `v26.9.28` vendored and
`mix ash_graphlaw.verify` passes). The snippets use `MyApp` as the application module. Nothing
below states output the tutorial did not observe; each step says what to look for. Standing of
the end-to-end run in this release: `UNKNOWN` `<<RECEIPT:claim-3>>`.

## The shape of what you build

```text
  test / caller
      |  Ash.create(:open, %{title: ...}, context: lease)
      v
  MyApp.Ticket  :open  --change-->  AshGraphLaw.Change.Admit (:ticket_shape)
      |                                  |  1. ceiling check (signed lease)   [no engine]
      |                                  |  2. MyApp.TicketShapeLaw.data/2     -> Turtle
      |                                  |  3. AshGraphLaw.law/3 -> Pool -> graphlaw.wasm
      v                                  v
  {:ok, ticket}                 Evidence in changeset context  |  Refusal in Ash error
```

## 1. Configure

`config/config.exs`:

```elixir
import Config

config :my_app, ash_domains: [MyApp.Domain]
config :ash_graphlaw, start_pool: true
```

In `config/test.exs` keep `start_pool: true` if you want the application to own the pool, or start
one in the test as step 7 shows.

## 2. A signer for leases

A signed lease is issued by a party you trust; the resource lists that party's public key. In a
real deployment the private key lives in a signer service. For a tutorial, derive a deterministic
Ed25519 key pair from a fixed seed. The payload the engine verifies is the sorted-key JSON of the
lease, `payload_sha256` is its SHA-256, and `key_id` is the SHA-256 of the raw public key (this is
the construction `test/support/lease.ex` in this repository uses; the engine verifies it, this
module only builds the input).

```elixir
defmodule MyApp.Signer do
  @seed :binary.copy(<<7>>, 32)
  @far_future 4_000_000_000
  @scope ~w(admit:shacl derive:n3 derive:hooks admit:plan admit:require-receipt
            admit:require-signed-receipt derive:rdfs derive:owl-rl)

  @doc "Hex public key to list under `runtime trusted_keys`."
  def public_key_hex, do: Base.encode16(elem(keypair(), 0), case: :lower)

  @doc "A signed lease map for `ceiling` (`:observe | :select | :construct`)."
  def signed(ceiling, id \\ "tutorial-lease") do
    {pub, priv} = keypair()

    payload =
      ~s({"ceiling":"#{ceiling}","expires_unix":#{@far_future},"holder":"tutorial",) <>
        ~s("id":"#{id}","issued_unix":0,"scope":#{Jason.encode!(@scope)}})

    %{
      "lease" => %{
        "id" => id,
        "holder" => "tutorial",
        "ceiling" => Atom.to_string(ceiling),
        "scope" => @scope,
        "expires_unix" => @far_future,
        "issued_unix" => 0
      },
      "attestation" => %{
        "key_id" => sha256_hex(pub),
        "payload_sha256" => sha256_hex(payload),
        "signature" =>
          :eddsa
          |> :crypto.sign(:none, payload, [priv, :ed25519])
          |> Base.encode16(case: :lower)
      }
    }
  end

  @doc "Changeset context carrying the lease under the default key."
  def context(ceiling), do: %{graphlaw_lease: %{signed_lease: signed(ceiling)}}

  defp keypair, do: :crypto.generate_key(:eddsa, :ed25519, @seed)
  defp sha256_hex(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
```

A fixed seed in source is acceptable only because this key guards nothing. Never commit a real
signing key; see [Security Model](../topics/security_model.md).

## 3. The law module

The law module projects the changeset to RDF and names the engine steps. It implements
`AshGraphLaw.Law`: `data/2` returns `{:ok, %{text: ..., dialect: ...}}` and `steps/2` returns the
list of step maps.

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
    body =
      case Ash.Changeset.get_attribute(changeset, :title) do
        nil -> "<urn:ticket:new> a ex:Ticket ."
        title -> "<urn:ticket:new> a ex:Ticket ; ex:title #{inspect(title)} ."
      end

    {:ok, %{text: "@prefix ex: <https://example.org/> .\n" <> body, dialect: "turtle"}}
  end

  @impl true
  def steps(_changeset, _admission), do: [%{"step" => "shacl", "shapes" => @shapes}]
end
```

`inspect/1` renders an Elixir string as a double-quoted literal, which is valid Turtle for simple
text. A title containing a backslash or an unusual control character needs real escaping; for
arbitrary user text prefer the default projection (`AshGraphLaw.Projection.Default`), which emits
escaped N-Triples. See [Write a Law Module](../how_to/write_a_law_module.md).

## 4. Resource and domain

```elixir
defmodule MyApp.Ticket do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  ets do
    private? true
  end

  graphlaw do
    runtime do
      timeout_ms 5000
      max_skew_secs 60
      trusted_keys [MyApp.Signer.public_key_hex()]
    end

    admission :ticket_shape do
      step :shacl
      ceiling :construct
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

defmodule MyApp.Domain do
  use Ash.Domain

  resources do
    resource MyApp.Ticket
  end
end
```

Compile with `mix compile --warnings-as-errors`. The Spark verifier
(`AshGraphLaw.Contract.validate/1`) runs at compile time: a duplicate admission name, a payload
step without a `law` module, a malformed `trusted_keys` entry or a non-positive `timeout_ms` fails
the build rather than a request. Try it: delete the `law` line and recompile; the build reports
the missing law module instead of admitting vacuously.

## 5. Observe the ceiling gate (no engine needed)

The ceiling is checked before any engine call. With no lease the `:construct` ceiling is unmet:

```elixir
{:error, error} =
  MyApp.Ticket
  |> Ash.Changeset.for_create(:open, %{title: "Printer offline"})
  |> Ash.create()

AshGraphLaw.Error.codes(error)
```

The list contains `:ceiling_unmet`. A bare atom does not help either: passing
`context: %{graphlaw_lease: :construct}` still grants only `:observe`, because only a signed lease
counts. See [Authority Boundary](../topics/authority_boundary.md).

## 6. Observe admission (engine needed)

Positive control first, with a signed lease at `:construct`:

```elixir
{:ok, ticket} =
  MyApp.Ticket
  |> Ash.Changeset.for_create(:open, %{title: "Printer offline"},
    context: MyApp.Signer.context(:construct)
  )
  |> Ash.create()
```

Now the negative case. Omit the title; the shape requires `ex:title` with `sh:minCount 1`:

```elixir
{:error, error} =
  MyApp.Ticket
  |> Ash.Changeset.for_create(:open, %{}, context: MyApp.Signer.context(:construct))
  |> Ash.create()

[%AshGraphLaw.Refusal{code: code, class: class, broken_term: term}] =
  AshGraphLaw.Error.refusals(error)
```

Look for `code` equal to `:not_admitted`, `class` equal to `:refused_admission`. `term` is the
Chatman failure-taxonomy term the refusal witnesses. Then a lease from a signer the resource does
not trust: sign with a different seed and expect `:lease_refused` with class `:refused_authority`.
The claim passes the pre-check; the engine verifies signature and signer and refuses.

## 7. Read the Evidence

`Ash.create/1` returns the record, not the changeset, so capture Evidence in an `after_action`
hook or call `AshGraphLaw.law/3` directly. This snippet uses the library API directly against the
same law:

```elixir
changeset = Ash.Changeset.for_create(MyApp.Ticket, :open, %{title: "Printer offline"})
{:ok, data} = MyApp.TicketShapeLaw.data(changeset, nil)
steps = MyApp.TicketShapeLaw.steps(changeset, nil)

{:ok, %AshGraphLaw.Admitted{} = admitted} =
  AshGraphLaw.law(data, steps, signed_lease: MyApp.Signer.signed(:construct),
                  trusted_keys: [MyApp.Signer.public_key_hex()])

evidence = AshGraphLaw.Evidence.new(:ticket_shape, admitted, nil)
AshGraphLaw.Standing.of({:ok, admitted})
```

`Standing.of/1` returns `:PARTIAL_ALIVE`: the admission was observed on this exact input and its
consequence has not run. The evidence carries `wasm_sha256` only when you pass it in; the action
path fills the input digest, engine digest and lease identity for you. Replay is covered in
[Replay Admission Evidence](../how_to/replay_admission_evidence.md).

## 8. Test it

Chicago style: real resource, real ETS data layer, real pool, no mocks. Positive control before
negatives; the ceiling test needs no engine, the admission tests carry `:wasm`.

```elixir
defmodule MyApp.TicketTest do
  use ExUnit.Case, async: false

  alias AshGraphLaw.Error

  defp open(attrs, context) do
    MyApp.Ticket
    |> Ash.Changeset.for_create(:open, attrs, context: context)
    |> Ash.create()
  end

  test "no lease is refused before the engine is called" do
    assert {:error, error} = open(%{title: "x"}, %{})
    assert :ceiling_unmet in Error.codes(error)
  end

  @tag :wasm
  test "a signed lease and a title are admitted" do
    assert {:ok, %{title: "Printer offline"}} =
             open(%{title: "Printer offline"}, MyApp.Signer.context(:construct))
  end

  @tag :wasm
  test "a missing title is not admitted" do
    assert {:error, error} = open(%{}, MyApp.Signer.context(:construct))
    assert :not_admitted in Error.codes(error)
  end
end
```

Run `mix test` for the wasm-free test and `mix test --include wasm` for all three. `:wasm` tests
need the vendored engine and a running pool (`start_pool: true` in `config/test.exs`, or
`start_supervised!({AshGraphLaw.Pool, size: 1})`). See
[Test Resources That Use Admissions](../how_to/test_resources_that_use_admissions.md).

## What you learned

- Admission is a declared, named unit on an action, not a hook you write by hand.
- The ceiling gate runs first and needs a signed lease; the engine then verifies that lease.
- Every failure is a `Refusal` with a closed `code`, `class` and `broken_term`.
- An admitted result is `:PARTIAL_ALIVE` at most, and grants no authority.

## See Also

- [First Admitted Action](first_admitted_action.md)
- [Declare an Admission](../how_to/declare_an_admission.md)
- [Mint and Verify a Signed Lease](../how_to/mint_and_verify_a_signed_lease.md)
- [Handle Refusals](../how_to/handle_refusals.md)
- [Troubleshooting](../topics/troubleshooting.md)
- [Security Model](../topics/security_model.md)
