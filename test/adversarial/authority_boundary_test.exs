# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits adversarial courts.

defmodule AshGraphLaw.Adversarial.AuthorityBoundaryTest do
  @moduledoc """
  Adversarial court for the authority boundary: GraphLaw derives and validates; it never
  authorizes.

    * an admitted action leaves every Ash authorization field of the changeset (actor,
      tenant, `authorize?`, and the lease itself) exactly as the caller set it;
    * admission evidence carries no authority field and its standing is derived, never
      accepted from a caller, and never `:ALIVE`;
    * `AshGraphLaw.Standing.of/1` cannot be talked into `:ALIVE` by hostile inputs.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Authority
  alias AshGraphLaw.Test.Lease

  alias AshGraphLaw.{Admitted, Evidence, Refusal, Standing}
  alias AshGraphLaw.Test.Ticket

  @authority_keys [:actor, :tenant, :authorize?]

  defp snapshot(%Ash.Changeset{} = cs) do
    private = Map.get(cs.context, :private, %{})

    %{
      authority: Map.take(private, @authority_keys),
      tenant: cs.tenant,
      context: Map.take(cs.context, [:graphlaw_lease, :caller_marker])
    }
  end

  describe "Standing.of/1" do
    test "positive control: an admitted result is :PARTIAL_ALIVE" do
      admitted = %Admitted{states: ["a"], receipts: [], nquads: ""}
      assert Standing.of({:ok, admitted}) == :PARTIAL_ALIVE
    end

    test "no refusal code, in any class, yields :ALIVE" do
      standings =
        for code <- Refusal.codes() do
          Standing.of({:error, Refusal.new(code, "m")})
        end

      refute :ALIVE in standings
      assert Enum.all?(standings, &Standing.valid?/1)
      assert Enum.sort(Enum.uniq(standings)) == Enum.sort([:BLOCKED, :UNKNOWN, :UNSUPPORTED])
    end

    test "an engine response that claims ALIVE, authority or admission is not believed" do
      hostile_raw = %{
        "standing" => "ALIVE",
        "ok" => true,
        "authorized" => true,
        "authority" => "root",
        "states" => [],
        "receipts" => [],
        "nquads" => ""
      }

      assert Standing.of({:ok, Admitted.from_map(hostile_raw)}) == :PARTIAL_ALIVE

      for other <- [
            :ALIVE,
            "ALIVE",
            {:ok, :ALIVE},
            {:ok, %{standing: :ALIVE}},
            {:ok, hostile_raw},
            nil,
            %{},
            {:error, :ALIVE}
          ] do
        refute Standing.of(other) == :ALIVE
        assert Standing.of(other) == :UNKNOWN
      end
    end
  end

  describe "Evidence" do
    setup do
      %{admitted: %Admitted{states: ["s1", "s2"], receipts: [], nquads: "", raw: %{}}}
    end

    test "positive control: evidence of an admission is :PARTIAL_ALIVE and digest-bound", %{admitted: admitted} do
      ev = Evidence.new(:probe, admitted, String.duplicate("a", 64), [])
      assert ev.standing == :PARTIAL_ALIVE
      assert ev.digest == Evidence.digest(ev)
    end

    test "a caller cannot inject a standing, authority or extra field through options", %{admitted: admitted} do
      digest = String.duplicate("a", 64)

      # positive control: the documented options are accepted and standing is still derived
      ev = Evidence.new(:probe, admitted, digest, wasm_sha256: digest, graphlaw_release: "26.9.28")
      assert ev.standing == :PARTIAL_ALIVE

      for opts <- [
            [standing: :ALIVE],
            [authorized: true],
            [authority: :root],
            [standing: :ALIVE, authority: :root, authorized: true]
          ] do
        assert_raise ArgumentError, ~r/unknown AshGraphLaw.Evidence.new\/4 options/, fn ->
          Evidence.new(:probe, admitted, digest, opts)
        end
      end
    end

    test "a lease is recorded only as an Authority identity, never as free-form data", %{admitted: admitted} do
      digest = String.duplicate("a", 64)
      identity = Authority.identity(Lease.container(:construct))

      # positive control: a real identity is accepted, recorded, and part of the digested content
      ev = Evidence.new(:probe, admitted, digest, lease: identity)
      assert ev.standing == :PARTIAL_ALIVE
      assert ev.lease == identity
      assert ev.digest != Evidence.new(:probe, admitted, digest, []).digest

      for bad <- [
            :root,
            "construct",
            %{ceiling: :construct},
            %{identity | ceiling: :root},
            Map.put(identity, :extra_grant, true)
          ] do
        assert_raise ArgumentError, fn -> Evidence.new(:probe, admitted, digest, lease: bad) end
      end
    end

    test "evidence has exactly the observation fields and no authority field", %{admitted: admitted} do
      ev = Evidence.new(:probe, admitted, String.duplicate("a", 64), [])

      assert ev |> Map.from_struct() |> Map.keys() |> Enum.sort() ==
               Enum.sort([
                 :admission,
                 :standing,
                 :input_digest,
                 :graph_ids,
                 :receipts,
                 :digest,
                 :wasm_sha256,
                 :graphlaw_release,
                 :lease
               ])

      keys = ev |> Evidence.to_map() |> Map.keys()
      refute Enum.any?(keys, &(&1 =~ ~r/authori|permission|actor|grant/i))
    end
  end

  describe "an :ok admission through Ash (real engine)" do
    @describetag :wasm

    setup do
      start_pool!(size: 1)
      Ash.DataLayer.Ets.stop(Ticket)
      on_exit(fn -> Ash.DataLayer.Ets.stop(Ticket) end)
      :ok
    end

    test "leaves actor, tenant, authorize? and lease untouched and stores only :PARTIAL_ALIVE evidence" do
      parent = self()
      actor = %{id: "user-1", role: :reader}

      changeset =
        Ticket
        |> Ash.Changeset.for_create(:open, %{title: "authority probe"},
          actor: actor,
          authorize?: false,
          context: Map.put(Lease.context(:construct), :caller_marker, :kept)
        )

      before = snapshot(changeset)
      # positive control for the snapshot: it really captures the caller's authority
      assert before.authority[:actor] == actor
      assert before.context.caller_marker == :kept

      assert {:ok, _record} =
               changeset
               |> Ash.Changeset.after_action(fn cs, record ->
                 send(parent, {:after, cs.context, snapshot(cs)})
                 {:ok, record}
               end)
               |> Ash.create()

      assert_receive {:after, context, after_snapshot}
      assert %Evidence{standing: standing} = context.graphlaw
      assert standing == :PARTIAL_ALIVE

      assert after_snapshot == before
      assert Map.take(context, [:authorized, :authorization, :permission, :permissions, :actor, :authorize?]) == %{}
    end

    test "a refused admission changes no authority either, and never reports :ALIVE" do
      parent = self()

      result =
        Ticket
        |> Ash.Changeset.for_create(:open, %{}, actor: %{id: "u"}, context: Lease.context(:construct))
        |> Ash.Changeset.after_action(fn cs, record ->
          send(parent, {:unexpected, cs.context})
          {:ok, record}
        end)
        |> Ash.create()

      assert {:error, error} = result
      assert AshGraphLaw.Error.codes(error) == [:not_admitted]
      refute_received {:unexpected, _}

      for refusal <- AshGraphLaw.Error.refusals(error) do
        refute Standing.of({:error, refusal}) == :ALIVE
      end
    end
  end
end
