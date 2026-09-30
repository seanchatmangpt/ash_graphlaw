# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.ScriptedHost do
  @moduledoc """
  UNSUPPORTED(generator-capability): a hand-written REAL implementation of the host request
  interface (`{:request, body, op, timeout}` call, `:members` registry membership), not a mock.
  It runs no wasm: it decodes the request body exactly as the engine boundary would, applies a
  scripted per-op behaviour and keeps real counters, so pool routing can be judged on final state.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec served(pid()) :: non_neg_integer()
  def served(pid), do: GenServer.call(pid, :served)

  @impl true
  def init(opts) do
    {:ok, _} = Registry.register(Keyword.fetch!(opts, :registry), :members, nil)
    {:ok, %{served: 0, work_ms: Keyword.get(opts, :work_ms, 0)}}
  end

  @impl true
  def handle_call(:served, _from, state), do: {:reply, state.served, state}

  def handle_call({:request, body, op, _timeout}, _from, state) do
    request = Jason.decode!(body)
    if state.work_ms > 0, do: Process.sleep(:rand.uniform(state.work_ms))
    reply = {:ok, %{"ok" => true, "op" => op, "id" => request["id"], "member" => inspect(self())}}
    {:reply, reply, %{state | served: state.served + 1}}
  end

  def handle_call(:status, _from, state), do: {:reply, {:ok, :loaded}, state}
end

defmodule AshGraphLaw.Property.PoolTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite; real Pool, real Registry,
  # scripted REAL host implementation (ScriptedHost above), no wasm required.
  use AshGraphLaw.Test.PropertyCase, async: false

  alias AshGraphLaw.Pool
  alias AshGraphLaw.Property.ScriptedHost

  @moduletag :slow

  defp start_members!(size, opts \\ []) do
    start_supervised!({Registry, keys: :duplicate, name: Pool.registry()})

    for i <- 1..size do
      start_supervised!(Supervisor.child_spec({ScriptedHost, [registry: Pool.registry()] ++ opts}, id: {:scripted, i}))
    end
  end

  describe "positive controls" do
    test "an empty registry refuses with :host_not_started" do
      assert {:error, %Refusal{code: :host_not_started, class: :blocked_resource}} =
               Pool.request(%{"op" => "capabilities"})
    end

    test "a single scripted member answers one request" do
      [pid] = start_members!(1)
      assert Pool.members() == [pid]
      assert {:ok, %{"ok" => true, "id" => 7}} = Pool.request(%{"op" => "ping", "id" => 7})
      assert ScriptedHost.served(pid) == 1
    end
  end

  describe "Pool.request/2 under concurrent load" do
    property "every caller gets its own answer and the members serve exactly N requests" do
      check all(
              size <- integer(1..4),
              callers <- integer(1..40),
              work_ms <- member_of([0, 3]),
              max_runs: max_runs(25)
            ) do
        {:ok, sup} = Supervisor.start_link([], strategy: :one_for_one)
        {:ok, _} = Supervisor.start_child(sup, {Registry, keys: :duplicate, name: Pool.registry()})

        members =
          for i <- 1..size do
            {:ok, pid} =
              Supervisor.start_child(
                sup,
                Supervisor.child_spec({ScriptedHost, [registry: Pool.registry(), work_ms: work_ms]}, id: {:scripted, i})
              )

            pid
          end

        try do
          results =
            1..callers
            |> Task.async_stream(fn id -> {id, Pool.request(%{"op" => "ping", "id" => id})} end,
              max_concurrency: callers,
              timeout: 30_000
            )
            |> Enum.map(fn {:ok, result} -> result end)

          assert length(results) == callers

          for {id, result} <- results do
            assert {:ok, %{"ok" => true, "id" => ^id, "op" => "ping"}} = result
          end

          assert members |> Enum.map(&ScriptedHost.served/1) |> Enum.sum() == callers
          assert Enum.sort(Pool.members()) == Enum.sort(members)
        after
          Supervisor.stop(sup)
        end
      end
    end

    property "pick/1 only ever returns a registered member" do
      check all(size <- integer(1..4), picks <- integer(1..20), max_runs: max_runs(25)) do
        {:ok, sup} = Supervisor.start_link([], strategy: :one_for_one)
        {:ok, _} = Supervisor.start_child(sup, {Registry, keys: :duplicate, name: Pool.registry()})

        members =
          for i <- 1..size do
            {:ok, pid} =
              Supervisor.start_child(
                sup,
                Supervisor.child_spec({ScriptedHost, [registry: Pool.registry()]}, id: {:scripted, i})
              )

            pid
          end

        try do
          for _ <- 1..picks, do: assert(Pool.pick() in members)
        after
          Supervisor.stop(sup)
        end
      end
    end

    property "a malformed encoding is refused by the codec before any member is touched" do
      check all(bad <- invalid_utf8(), max_runs: max_runs(25)) do
        {:ok, sup} = Supervisor.start_link([], strategy: :one_for_one)
        {:ok, _} = Supervisor.start_child(sup, {Registry, keys: :duplicate, name: Pool.registry()})
        {:ok, pid} = Supervisor.start_child(sup, {ScriptedHost, [registry: Pool.registry()]})

        try do
          assert {:error, %Refusal{code: :invalid_encoding}} = Pool.request(%{"op" => "ping", "text" => bad})
          assert ScriptedHost.served(pid) == 0
        after
          Supervisor.stop(sup)
        end
      end
    end
  end
end
