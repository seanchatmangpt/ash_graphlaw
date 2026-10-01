# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.HostRecycleLoadTest do
  @moduledoc """
  Host recycling under concurrent load, against the real pinned engine.

  `recycle_bytes: 1` forces a recycle after every successful transaction (linear memory always
  exceeds one byte); a starved host recycles after every failed one. Concurrent callers must
  each get a typed answer, the recycle count in `Host.info/1` must equal the recycle telemetry
  observed for that host, and the instance must be replaced rather than left dead.

  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  @moduletag :wasm
  @moduletag :slow

  alias AshGraphLaw.{Host, Refusal}

  @nt "<urn:a:x> <urn:a:p> <urn:a:y> .\n"

  defp law_req do
    %{"op" => "law", "data" => %{"text" => @nt, "dialect" => "ntriples"}, "steps" => [%{"step" => "rdfs"}]}
  end

  def forward(_event, measurements, metadata, pid), do: send(pid, {:recycled, measurements, metadata})

  setup do
    handler = "ash-graphlaw-recycle-load-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler, [:ash_graphlaw, :host, :recycle], &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  defp drain_recycles(acc \\ []) do
    receive do
      {:recycled, m, meta} -> drain_recycles([{m, meta} | acc])
    after
      500 -> Enum.reverse(acc)
    end
  end

  test "positive control: a host that is not asked to recycle does not recycle under load" do
    host = start_host!([])
    assert {:ok, %{"ok" => true}} = Host.request(host, law_req())
    results = for _ <- 1..10, do: Host.request(host, law_req())
    assert Enum.all?(results, &match?({:ok, %{"ok" => true}}, &1))
    assert {:ok, %{recycles: 0}} = Host.info(host)
    assert drain_recycles() == []
  end

  test "recycle_bytes: 1 recycles under 40 concurrent callers and every caller is served" do
    host = start_host!(recycle_bytes: 1)

    results =
      1..40
      |> Task.async_stream(fn _ -> Host.request(host, law_req(), timeout: 30_000) end,
        max_concurrency: 40,
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.all?(results, &match?({:ok, %{"ok" => true}}, &1)),
           inspect(Enum.reject(results, &match?({:ok, %{"ok" => true}}, &1)))

    # a fresh instance answers exactly like the one it replaced
    assert results |> Enum.uniq() |> length() == 1

    assert {:ok, %{recycles: recycles}} = Host.info(host)
    assert recycles >= 1

    events = drain_recycles()
    assert length(events) == recycles
    assert Enum.all?(events, fn {_m, meta} -> meta.reason == :memory_high_water end)
    assert events |> Enum.map(fn {m, _} -> m.count end) |> Enum.sort() == Enum.to_list(1..recycles)
  end

  test "a starved host recycles after every refused transaction and stays alive under concurrent load" do
    host = start_host!(fuel: 1)

    results =
      1..20
      |> Task.async_stream(fn _ -> Host.request(host, law_req(), timeout: 30_000) end,
        max_concurrency: 20,
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.all?(results, &match?({:error, %Refusal{class: :blocked_resource}}, &1)),
           inspect(Enum.reject(results, &match?({:error, %Refusal{class: :blocked_resource}}, &1)))

    assert Process.alive?(host)

    # every failure recycled once (a saturated caller would be a :saturated refusal, not asserted here)
    events = drain_recycles()
    assert events != []
    assert Enum.all?(events, fn {_m, meta} -> meta.reason in [:fuel_exhausted, :call_trapped] end)
  end

  test "an instance that is killed mid-load is replaced and later callers are served" do
    host = start_host!([])
    assert {:ok, %{"ok" => true}} = Host.request(host, law_req())

    tasks = for _ <- 1..20, do: Task.async(fn -> Host.request(host, law_req(), timeout: 30_000) end)

    # the instance is the host's linked child; killing it is an external crash of the engine
    %{pid: instance} = :sys.get_state(host)
    assert is_pid(instance) and instance != host
    Process.exit(instance, :kill)

    results = Enum.map(tasks, &Task.await(&1, 120_000))

    # every in-flight caller got a typed answer: a response or a Refusal, never an exit
    assert Enum.all?(results, &(match?({:ok, %{}}, &1) or match?({:error, %Refusal{}}, &1)))
    assert Process.alive?(host)

    assert eventually_ok(fn -> Host.request(host, law_req(), timeout: 30_000) end)
  end

  defp eventually_ok(fun, attempts \\ 50) do
    case fun.() do
      {:ok, %{"ok" => true}} ->
        true

      _ when attempts > 0 ->
        Process.sleep(100)
        eventually_ok(fun, attempts - 1)

      _ ->
        false
    end
  end
end
