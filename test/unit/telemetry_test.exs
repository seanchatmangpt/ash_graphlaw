# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written telemetry court.
defmodule AshGraphLaw.Unit.TelemetryTest do
  @moduledoc """
  Real `:telemetry` handlers observe `AshGraphLaw.Telemetry.capability/3`. Engine-touching
  tests (typed ops through the real wasm) are tagged `:wasm`; the span-semantics tests use
  plain functions and need no engine.
  """
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Telemetry

  @capability_events [
    [:ash_graphlaw, :capability, :start],
    [:ash_graphlaw, :capability, :stop],
    [:ash_graphlaw, :capability, :exception]
  ]

  setup do
    id = "telemetry-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        id,
        @capability_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  test "positive control: events/0 lists the capability span and the untouched admission event" do
    events = Telemetry.events()
    for e <- @capability_events, do: assert(e in events)
    assert [:ash_graphlaw, :admission, :stop] in events
  end

  test "ok result emits start then stop with outcome :ok and returns the value unchanged" do
    assert {:ok, 1} = Telemetry.capability("sniff", [server: :srv], fn -> {:ok, 1} end)

    assert_received {:event, [:ash_graphlaw, :capability, :start], %{system_time: st}, %{op: "sniff", server: :srv}}

    assert is_integer(st)

    assert_received {:event, [:ash_graphlaw, :capability, :stop], %{duration: d},
                     %{op: "sniff", outcome: :ok, refusal_code: nil, server: :srv}}

    assert is_integer(d) and d >= 0
    refute_received {:event, [:ash_graphlaw, :capability, :exception], _, _}
  end

  test "refusal result emits stop with outcome :refused and the refusal code" do
    refusal = AshGraphLaw.Refusal.build(:unknown_capability, "nope", %{})
    assert {:error, ^refusal} = Telemetry.capability("nope", [], fn -> {:error, refusal} end)

    assert_received {:event, [:ash_graphlaw, :capability, :stop], _,
                     %{op: "nope", outcome: :refused, refusal_code: :unknown_capability}}
  end

  test "exception emits :exception metadata and re-raises the original error" do
    assert_raise RuntimeError, "boom", fn ->
      Telemetry.capability("parse", [], fn -> raise "boom" end)
    end

    assert_received {:event, [:ash_graphlaw, :capability, :start], _, %{op: "parse"}}

    assert_received {:event, [:ash_graphlaw, :capability, :exception], %{duration: _},
                     %{
                       op: "parse",
                       outcome: :exception,
                       refusal_code: nil,
                       kind: :error,
                       reason: %RuntimeError{message: "boom"}
                     }}

    refute_received {:event, [:ash_graphlaw, :capability, :stop], _, _}
  end

  test "throws are reported as exceptions and re-thrown" do
    assert :thrown = catch_throw(Telemetry.capability("parse", [], fn -> throw(:thrown) end))
    assert_received {:event, [:ash_graphlaw, :capability, :exception], _, %{kind: :throw, reason: :thrown}}
  end

  describe "typed ops through the real engine" do
    @describetag :wasm

    setup do
      %{server: start_host!([])}
    end

    test "an ok typed op emits start and stop(:ok)", %{server: server} do
      assert {:ok, %AshGraphLaw.Result.Sniff{}} =
               AshGraphLaw.Capability.API.sniff(%{text: "<urn:a> <urn:b> <urn:c> ."}, server: server)

      assert_received {:event, [:ash_graphlaw, :capability, :start], _, %{op: "sniff", server: ^server}}

      assert_received {:event, [:ash_graphlaw, :capability, :stop], %{duration: _},
                       %{op: "sniff", outcome: :ok, refusal_code: nil}}
    end

    test "a refused typed op emits stop(:refused) with a code", %{server: server} do
      assert {:error, %AshGraphLaw.Refusal{code: code}} =
               AshGraphLaw.Capability.API.n3(%{text: "{ ?x a } =>"}, server: server)

      assert_received {:event, [:ash_graphlaw, :capability, :stop], _,
                       %{op: "n3", outcome: :refused, refusal_code: ^code}}

      assert is_atom(code) and code != nil
    end
  end
end
