# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Ash.ChangeTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Test.Lease

  alias AshGraphLaw.Error
  alias AshGraphLaw.Evidence
  alias AshGraphLaw.Test.Ticket

  @moduletag :wasm

  setup do
    start_pool!([])
    Ash.DataLayer.Ets.stop(Ticket)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Ticket) end)
    :ok
  end

  def handle_event(event, measurements, metadata, pid), do: send(pid, {:telemetry, event, measurements, metadata})

  # Adds a real after_action hook that reports the changeset context the admission wrote.
  defp create_capturing(params, lease \\ :construct) do
    parent = self()

    Ticket
    |> Ash.Changeset.for_create(:open, params, context: Lease.context(lease))
    |> Ash.Changeset.after_action(fn changeset, record ->
      send(parent, {:context, changeset.context})
      {:ok, record}
    end)
    |> Ash.create()
  end

  describe "create :open" do
    test "a conformant title is admitted, persisted and carries evidence" do
      assert {:ok, ticket} = create_capturing(%{title: "Fix the build"})
      assert_receive {:context, %{graphlaw: %Evidence{} = evidence}}

      assert evidence.admission == :ticket_shape
      assert evidence.standing == :PARTIAL_ALIVE
      assert is_binary(evidence.digest) and byte_size(evidence.digest) == 64
      assert is_binary(evidence.input_digest) and byte_size(evidence.input_digest) == 64
      assert evidence.digest == Evidence.digest(evidence)

      assert [%{id: id}] = Ash.read!(Ticket)
      assert id == ticket.id
    end

    test "evidence is stable: the same input yields the same input digest and evidence digest" do
      assert {:ok, _} = create_capturing(%{title: "Stable title"})
      assert_receive {:context, %{graphlaw: first}}
      assert {:ok, _} = create_capturing(%{title: "Stable title"})
      assert_receive {:context, %{graphlaw: second}}

      assert first.input_digest == second.input_digest
      assert first.digest == second.digest

      assert {:ok, _} = create_capturing(%{title: "A different title"})
      assert_receive {:context, %{graphlaw: third}}
      assert third.input_digest != first.input_digest
    end

    test "a violating input is refused with :not_admitted and nothing is persisted" do
      # positive control: the same action admits a conformant title in this test's own state
      assert {:ok, _} = create_capturing(%{title: "Control"})
      assert [%{title: "Control"}] = Ash.read!(Ticket)

      assert {:error, %Ash.Error.Invalid{} = error} = create_capturing(%{})
      assert Error.codes(error) == [:not_admitted]
      assert [refusal] = Error.refusals(error)
      assert refusal.class == :refused_admission
      assert refusal.broken_term == :mu_on_O

      # only the control record exists: the refused create wrote nothing
      assert [%{title: "Control"}] = Ash.read!(Ticket)
    end
  end

  describe "update :close (ceiling :select)" do
    setup do
      {:ok, ticket} = create_capturing(%{title: "Close me"})
      %{ticket: ticket}
    end

    test "positive control: with a :select lease the update is admitted", %{ticket: ticket} do
      assert {:ok, _} =
               ticket
               |> Ash.Changeset.for_update(:close, %{}, context: Lease.context(:select))
               |> Ash.update()
    end

    test "without a lease the ceiling is unmet and the engine is never called", %{ticket: ticket} do
      handler = "ash-graphlaw-change-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach_many(
          handler,
          [[:ash_graphlaw, :host, :call, :stop], [:ash_graphlaw, :admission, :stop]],
          &__MODULE__.handle_event/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      assert {:error, %Ash.Error.Invalid{} = error} =
               ticket |> Ash.Changeset.for_update(:close, %{}) |> Ash.update()

      assert Error.codes(error) == [:ceiling_unmet]
      assert [%{class: :refused_authority, broken_term: :R_missing_authority}] = Error.refusals(error)

      # the admission event proves the change ran; the absence of a host event proves the engine did not
      assert_receive {:telemetry, [:ash_graphlaw, :admission, :stop], _, %{outcome: :refused, code: :ceiling_unmet}}
      refute_receive {:telemetry, [:ash_graphlaw, :host, :call, :stop], _, _}, 200
    end

    test "an :observe lease is below :select and is refused", %{ticket: ticket} do
      assert {:error, error} =
               ticket |> Ash.Changeset.for_update(:close, %{}, context: Lease.context(:observe)) |> Ash.update()

      assert Error.codes(error) == [:ceiling_unmet]
    end
  end
end
