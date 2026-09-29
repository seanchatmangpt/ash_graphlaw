# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits adversarial courts.

defmodule AshGraphLaw.Adversarial.LeaseCeilingTest do
  @moduledoc """
  Adversarial court for the authority ceiling.

  An admission's `ceiling` can only be met by a SIGNED lease of at least that ceiling found under
  the configured context key. A caller cannot self-grant: bare ceiling atoms, `%{ceiling: ...}` maps
  and keyword lists, unsigned `:lease` entries, string-keyed look-alikes, the wrong key and lower
  ceilings all refuse with `:ceiling_unmet` BEFORE the engine is called: the admission telemetry
  event is emitted and the host-call event never is. Non-`:wasm` controls show a signed lease
  passing the ceiling check (the failure moves on to the engine boundary); the `:wasm` controls
  show the same lease admitted for real, and forged signed leases refused by the engine.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.Ticket

  @host_event [:ash_graphlaw, :host, :call, :stop]
  @admission_event [:ash_graphlaw, :admission, :stop]

  def forward(event, measurements, metadata, pid), do: send(pid, {:telemetry, event, measurements, metadata})

  setup do
    Ash.DataLayer.Ets.stop(Ticket)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Ticket) end)

    handler = "ash-graphlaw-lease-ceiling-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach_many(handler, [@host_event, @admission_event], &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  # Refused attempts use the default titles; positive controls pass their own, so "nothing named
  # `ceiling probe` was persisted / closed" is a precise statement about the refused attempt only.
  # (`Ash.DataLayer.Ets.stop/1` is called only in setup and on_exit: a table that has been stopped
  # cannot be read or written again within the same test.)
  defp open(context, title \\ "ceiling probe") do
    Ticket
    |> Ash.Changeset.for_create(:open, %{title: title}, context: context)
    |> Ash.create()
  end

  defp close(context, title \\ "close probe") do
    ticket = Ticket |> Ash.Changeset.for_create(:seed, %{title: title}) |> Ash.create!()

    ticket
    |> Ash.Changeset.for_update(:close, %{}, context: context)
    |> Ash.update()
  end

  defp assert_ceiling_refused({:error, error}, required) do
    assert Error.codes(error) == [:ceiling_unmet]
    assert [%{class: :refused_authority, broken_term: :R_missing_authority, details: details}] = Error.refusals(error)
    assert details.required == required

    assert_receive {:telemetry, @admission_event, _, %{outcome: :refused, code: :ceiling_unmet}}
    refute_receive {:telemetry, @host_event, _, _}, 100
    tickets = Ash.read!(Ticket)
    refute Enum.any?(tickets, &(&1.title == "ceiling probe")), "a refused open was persisted"
    refute Enum.any?(tickets, &(&1.title == "close probe" and &1.state == :closed)), "a refused close took effect"
  end

  alias AshGraphLaw.Test.Lease

  defp signed(ceiling, opts \\ []), do: Lease.context(ceiling, opts)

  describe "ticket_shape requires :construct" do
    test "positive control: a signed :construct lease passes the ceiling check and reaches the engine boundary" do
      result = open(signed(:construct))

      case result do
        {:ok, _ticket} -> :ok
        {:error, error} -> refute :ceiling_unmet in Error.codes(error)
      end

      assert_receive {:telemetry, @admission_event, _, %{code: code}}
      refute code == :ceiling_unmet
    end

    test "a signed :select lease is below :construct" do
      assert_ceiling_refused(open(signed(:select)), :construct)
    end

    test "a signed :observe lease, no lease, and an empty lease all fail" do
      for context <- [signed(:observe), %{}, %{graphlaw_lease: %{}}, %{graphlaw_lease: nil}] do
        assert_ceiling_refused(open(context), :construct)
      end
    end

    test "a sufficient signed lease under an unexpected context key grants nothing" do
      for key <- [:lease, :graphlaw_lease_x, :ceiling, "graphlaw_lease", :graphlaw] do
        assert_ceiling_refused(open(%{key => Lease.container(:construct)}), :construct)
      end
    end

    test "a caller cannot self-grant: every unsigned shape grants only :observe" do
      unsigned = [
        :construct,
        "construct",
        %{ceiling: :construct},
        [ceiling: :construct],
        %{"ceiling" => "construct"},
        %{"ceiling" => :construct},
        %{ceiling: "construct"},
        %{lease: %{"ceiling" => "construct"}},
        %{lease: %{ceiling: :construct}, unverified_lease: true, now_unix: 0},
        %{signed_lease: nil, ceiling: :construct},
        %{signed_lease: "construct"},
        %{signed_lease: %{"lease" => %{"ceiling" => "root"}}},
        %{signed_lease: %{"lease" => %{"ceiling" => "Construct"}}},
        [{"ceiling", :construct}],
        {:construct},
        42
      ]

      for lease <- unsigned do
        assert_ceiling_refused(open(%{graphlaw_lease: lease}), :construct)
      end
    end

    test "the signed forms that do carry a construct claim pass the ceiling check (the refusals are not vacuous)" do
      signed_lease = Lease.signed(:construct)

      shapes = [%{signed_lease: signed_lease}, [signed_lease: signed_lease], %{signed_lease: atomize(signed_lease)}]

      for lease <- shapes do
        result = open(%{graphlaw_lease: lease})

        case result do
          {:ok, _} -> :ok
          {:error, error} -> refute :ceiling_unmet in Error.codes(error), "#{inspect(lease)} was refused on ceiling"
        end
      end
    end
  end

  describe "ticket_close requires :select" do
    test "positive control: a signed :select lease passes the ceiling check" do
      result = close(signed(:select))

      case result do
        {:ok, _} -> :ok
        {:error, error} -> refute :ceiling_unmet in Error.codes(error)
      end
    end

    test "signed :observe, a missing lease and a lease under the wrong key are below :select" do
      for context <- [signed(:observe), %{}, %{lease: Lease.container(:select)}, %{graphlaw_lease: :select}] do
        assert_ceiling_refused(close(context), :select)
      end
    end
  end

  describe "with the real engine" do
    @describetag :wasm

    setup do
      start_pool!(size: 2)
      :ok
    end

    test "positive control: a signed :construct lease is admitted and the engine is called" do
      assert {:ok, ticket} = open(signed(:construct), "admitted probe")
      assert ticket.title == "admitted probe"
      assert_receive {:telemetry, @host_event, _, _}
      assert_receive {:telemetry, @admission_event, _, %{outcome: :admitted, code: nil}}
    end

    test "a lower ceiling is refused without a single host call" do
      # positive control first, so the host-call probe is proven live in this test
      assert {:ok, _} = open(signed(:construct), "admitted probe")
      assert_receive {:telemetry, @host_event, _, _}
      flush_telemetry()

      assert_ceiling_refused(open(signed(:select)), :construct)
    end

    test "a sufficient signed :select lease admits the close plan for real, :observe does not" do
      assert {:ok, %{state: :closed}} = close(signed(:select), "closed probe")
      assert_receive {:telemetry, @host_event, _, _}
      flush_telemetry()

      assert_ceiling_refused(close(signed(:observe)), :select)
    end

    test "a forged signed lease passes the claim pre-check and is refused by the engine, never admitted" do
      # positive control: the same claim, correctly signed by the trusted signer, is admitted
      assert {:ok, _} = open(signed(:construct), "admitted probe")

      forged = [
        untrusted_signer: signed(:construct, signer: :untrusted),
        expired: signed(:construct, expires_unix: 100),
        tampered: signed(:construct, tamper: %{"ceiling" => "construct", "holder" => "mallory"}),
        upgraded_after_signing: signed(:observe, tamper: %{"ceiling" => "construct"})
      ]

      for {kind, context} <- forged do
        assert {:error, error} = open(context)

        assert :lease_refused in Error.codes(error),
               "#{kind} was not refused by the engine: #{inspect(Error.codes(error))}"

        refute Enum.any?(Ash.read!(Ticket), &(&1.title == "ceiling probe")), "#{kind} was persisted"
      end
    end

    test "trust anchors and the clock in caller context are ignored: only runtime.trusted_keys counts" do
      untrusted = Lease.signed(:construct, signer: :untrusted)
      pub = Lease.public_key_hex(:untrusted)

      container = %{signed_lease: untrusted, trusted_keys: [pub], max_skew_secs: 1_000_000_000, now_unix: 0}

      assert {:error, error} = open(%{graphlaw_lease: container})
      assert :lease_refused in Error.codes(error)
    end
  end

  defp atomize(%{"lease" => lease, "attestation" => att}), do: %{lease: atom_keys(lease), attestation: atom_keys(att)}
  defp atom_keys(map), do: Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)

  defp flush_telemetry do
    receive do
      {:telemetry, _, _, _} -> flush_telemetry()
    after
      0 -> :ok
    end
  end
end
