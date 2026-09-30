# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Ash.TelemetryTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Test.Lease

  alias AshGraphLaw.Test.Ticket

  @moduletag :wasm

  setup do
    start_pool!([])
    Ash.DataLayer.Ets.stop(Ticket)

    handler = "ash-graphlaw-telemetry-test-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler, [:ash_graphlaw, :admission, :stop], &__MODULE__.handle_event/4, self())

    on_exit(fn ->
      :telemetry.detach(handler)
      Ash.DataLayer.Ets.stop(Ticket)
    end)

    :ok
  end

  def handle_event(event, measurements, metadata, pid), do: send(pid, {:telemetry, event, measurements, metadata})

  defp create(params),
    do: Ticket |> Ash.Changeset.for_create(:open, params, context: Lease.context(:construct)) |> Ash.create()

  test "an admitted create emits outcome :admitted with standing :PARTIAL_ALIVE and no code" do
    assert {:ok, _} = create(%{title: "telemetry"})

    assert_receive {:telemetry, [:ash_graphlaw, :admission, :stop], %{duration: duration},
                    %{admission: :ticket_shape, outcome: :admitted, code: nil, standing: :PARTIAL_ALIVE}}

    assert is_integer(duration) and duration >= 0
  end

  test "a refused create emits outcome :refused with the typed code and a non-ALIVE standing" do
    assert {:ok, _} = create(%{title: "control"})
    assert_receive {:telemetry, _, _, %{outcome: :admitted}}

    assert {:error, _} = create(%{})

    assert_receive {:telemetry, [:ash_graphlaw, :admission, :stop], %{duration: _},
                    %{admission: :ticket_shape, outcome: :refused, code: :engine_refused, standing: standing}}

    assert standing == :UNKNOWN
    refute standing == :ALIVE
  end

  test "a ceiling refusal is reported on the same event with code :ceiling_unmet" do
    assert {:ok, ticket} = create(%{title: "close"})
    assert_receive {:telemetry, _, _, %{admission: :ticket_shape, outcome: :admitted}}

    assert {:error, _} = ticket |> Ash.Changeset.for_update(:close, %{}) |> Ash.update()

    assert_receive {:telemetry, [:ash_graphlaw, :admission, :stop], _,
                    %{admission: :ticket_close, outcome: :refused, code: :ceiling_unmet, standing: :UNKNOWN}}
  end
end
