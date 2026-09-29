# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits adversarial courts.

defmodule AshGraphLaw.Adversarial.ReplayDeterminismTest do
  @moduledoc """
  Adversarial court for replay determinism.

  The same input must yield a byte-identical projection and an identical evidence digest on
  every run: 100 repetitions, key-order permutations of engine payloads, and (under `:wasm`)
  across a real host recycle forced by a 1-byte recycle threshold. Every equality has a
  distinguishing control (a different input must differ), so a constant function cannot pass.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Test.Lease

  alias AshGraphLaw.{Admitted, Evidence, Receipt}
  alias AshGraphLaw.Projection.Default
  alias AshGraphLaw.Test.Ticket

  @runs 100

  def forward_recycle(_event, measurements, metadata, pid), do: send(pid, {:recycled, measurements, metadata})

  defp changeset(title), do: Ash.Changeset.for_create(Ticket, :open, %{title: title})

  defp projected(changeset) do
    assert {:ok, %{text: text, dialect: "ntriples"}} = Default.data(changeset, [])
    text
  end

  defp admitted(raw_order) do
    raw = Map.new(raw_order)

    %Admitted{
      states: ["state-a", "state-b"],
      receipts: [
        %Receipt{step: "shacl", parent: "state-a", child: "state-b", added: 3, authority: "purrdf::shapes", raw: raw}
      ],
      nquads: "<urn:a> <urn:b> <urn:c> .\n",
      raw: %{}
    }
  end

  describe "projection" do
    test "positive control: different titles project differently" do
      refute projected(changeset("alpha")) == projected(changeset("beta"))
    end

    test "#{@runs} fresh changesets of the same input project to one byte-identical text" do
      texts = for _ <- 1..@runs, do: projected(changeset("stable title"))
      assert [_one] = Enum.uniq(texts)
      assert hd(texts) =~ "stable title"
    end

    test "the projection of a stored record is stable across runs and independent of the generated id" do
      texts =
        for i <- 1..20 do
          ticket = Ash.create!(Ticket, %{title: "stored #{i}"}, action: :seed)
          Ash.Changeset.for_update(ticket, :close, %{}) |> projected() |> String.replace(ticket.id, "<ID>")
        end

      assert length(texts) == 20
      assert texts |> Enum.map(&String.replace(&1, ~r/stored \d+/, "stored N")) |> Enum.uniq() |> length() == 1
    end

    test "the input digest is the sha256 of the projected text and changes with it" do
      digest = fn cs -> :crypto.hash(:sha256, projected(cs)) |> Base.encode16(case: :lower) end
      assert digest.(changeset("x")) == digest.(changeset("x"))
      refute digest.(changeset("x")) == digest.(changeset("y"))
    end
  end

  describe "evidence digest" do
    test "positive control: a different input digest changes the evidence digest" do
      a = Evidence.new(:probe, admitted(a: 1), String.duplicate("a", 64), [])
      b = Evidence.new(:probe, admitted(a: 1), String.duplicate("b", 64), [])
      refute a.digest == b.digest
    end

    test "#{@runs} builds of the same evidence share one digest" do
      digests =
        for _ <- 1..@runs do
          Evidence.new(:probe, admitted(a: 1, b: [1, 2, %{"z" => 1, "y" => 2}]), String.duplicate("c", 64), []).digest
        end

      assert [digest] = Enum.uniq(digests)
      assert String.match?(digest, ~r/\A[0-9a-f]{64}\z/)
    end

    test "the digest does not depend on map key insertion order" do
      pairs = for i <- 1..40, do: {"key#{i}", %{"n#{i}" => i, "m#{i}" => [i, i + 1]}}
      shuffled = Enum.reverse(pairs)
      refute pairs == shuffled

      one = Evidence.new(:probe, admitted(pairs), String.duplicate("d", 64), [])
      two = Evidence.new(:probe, admitted(shuffled), String.duplicate("d", 64), [])
      assert one.digest == two.digest
    end

    test "the digest covers every field except itself" do
      base = Evidence.new(:probe, admitted(a: 1), String.duplicate("e", 64), wasm_sha256: "f")
      assert Evidence.digest(base) == base.digest
      assert Evidence.digest(%{base | digest: "garbage"}) == base.digest

      for change <- [
            %{admission: :other},
            %{input_digest: String.duplicate("0", 64)},
            %{graph_ids: ["different"]},
            %{receipts: []},
            %{wasm_sha256: "g"},
            %{graphlaw_release: "v0.0.0"}
          ] do
        refute Evidence.digest(Map.merge(base, change)) == base.digest, "#{inspect(change)} is not covered"
      end
    end

    test "canonical_json sorts keys at every depth" do
      assert Evidence.canonical_json(%{"b" => %{"z" => 1, "a" => 2}, "a" => [%{"y" => 1, "x" => 2}]}) ==
               ~s({"a":[{"x":2,"y":1}],"b":{"a":2,"z":1}})
    end
  end

  describe "across a host recycle (real engine)" do
    @describetag :wasm

    setup do
      # a 1-byte recycle threshold recycles the engine instance after every call
      start_pool!(size: 1, recycle_bytes: 1)
      Ash.DataLayer.Ets.stop(Ticket)
      on_exit(fn -> Ash.DataLayer.Ets.stop(Ticket) end)
      :ok
    end

    defp admit(title) do
      parent = self()

      result =
        Ticket
        |> Ash.Changeset.for_create(:open, %{title: title}, context: Lease.context(:construct))
        |> Ash.Changeset.after_action(fn cs, record ->
          send(parent, {:evidence, cs.context.graphlaw})
          {:ok, record}
        end)
        |> Ash.create()

      assert {:ok, _} = result
      assert_receive {:evidence, %Evidence{} = evidence}
      evidence
    end

    test "the same input yields the same evidence digest before and after recycles" do
      handler = "ash-graphlaw-recycle-#{System.unique_integer([:positive])}"

      :ok = :telemetry.attach(handler, [:ash_graphlaw, :host, :recycle], &__MODULE__.forward_recycle/4, self())

      on_exit(fn -> :telemetry.detach(handler) end)

      first = admit("replay me")
      digests = for _ <- 1..10, do: admit("replay me").digest

      assert Enum.uniq([first.digest | digests]) == [first.digest]
      # the recycle really happened: the determinism claim spans different engine instances
      assert_received {:recycled, _, _}

      other = admit("a different title")
      refute other.digest == first.digest
      refute other.input_digest == first.input_digest
    end
  end
end
