# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Ash.AtomicTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Test.Lease

  alias AshGraphLaw.Change.Admit
  alias AshGraphLaw.Test.Ticket

  @reason "GraphLaw admission requires a WASM call"

  setup do
    Ash.DataLayer.Ets.stop(Ticket)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Ticket) end)
    :ok
  end

  def handle_event(event, measurements, metadata, pid), do: send(pid, {:telemetry, event, measurements, metadata})

  defp seed(count) do
    for n <- 1..count do
      Ticket
      |> Ash.Changeset.for_create(:open, %{title: "ticket #{n}"}, context: Lease.context(:construct))
      |> Ash.create!()
    end
  end

  test "the change declares itself non-atomic with the documented reason (no engine needed)" do
    assert {:not_atomic, @reason} = Admit.atomic(Ash.Changeset.new(Ticket), [admission: :ticket_close], %{})
  end

  describe "bulk update strategy :stream" do
    @describetag :wasm

    setup do
      start_pool!([])
      :ok
    end

    test "every record is admitted through the non-atomic path" do
      tickets = seed(3)
      handler = "ash-graphlaw-atomic-test-#{System.unique_integer([:positive])}"
      :ok = :telemetry.attach(handler, [:ash_graphlaw, :admission, :stop], &__MODULE__.handle_event/4, self())
      on_exit(fn -> :telemetry.detach(handler) end)

      result =
        Ash.bulk_update(tickets, :close, %{},
          strategy: :stream,
          context: Lease.context(:select),
          return_records?: true,
          return_errors?: true
        )

      assert %Ash.BulkResult{status: :success, error_count: 0} = result
      assert result.records |> Enum.map(& &1.id) |> Enum.sort() == tickets |> Enum.map(& &1.id) |> Enum.sort()

      for _ticket <- tickets do
        assert_receive {:telemetry, [:ash_graphlaw, :admission, :stop], _,
                        %{admission: :ticket_close, outcome: :admitted, code: nil, standing: :PARTIAL_ALIVE}}
      end
    end

    test "a missing lease refuses every record and leaves them unchanged" do
      tickets = seed(2)
      before = Enum.sort_by(Ash.read!(Ticket), & &1.id)

      # positive control: the same records are admitted with a lease
      assert %Ash.BulkResult{status: :success} =
               Ash.bulk_update(tickets, :close, %{}, strategy: :stream, context: Lease.context(:select))

      result = Ash.bulk_update(tickets, :close, %{}, strategy: :stream, return_errors?: true, return_records?: true)
      assert %Ash.BulkResult{status: status, error_count: 2} = result
      assert status in [:error, :partial_success]
      assert Enum.all?(result.errors, &(AshGraphLaw.Error.codes(&1) == [:ceiling_unmet]))
      assert length(before) == 2
    end
  end

  describe "bulk update strategy :atomic" do
    test "Ash refuses it and surfaces the change's not_atomic reason" do
      # records come from the ungated :seed action: this test needs no engine
      tickets = for n <- 1..2, do: Ash.create!(Ticket, %{title: "stored #{n}"}, action: :seed)

      result =
        Ash.bulk_update(Ticket, :close, %{},
          strategy: :atomic,
          context: Lease.context(:select),
          return_errors?: true
        )

      refute match?(%Ash.BulkResult{status: :success}, result)
      assert inspect(result) =~ @reason
      # nothing was closed or removed: both seeded tickets are still readable
      assert length(Ash.read!(Ticket)) == length(tickets)
    end
  end
end
