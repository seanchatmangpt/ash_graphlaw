# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation.Collector do
  @moduledoc """
  ExUnit formatter that records the names of failed tests in a public ETS table.

  Development tooling. UNSUPPORTED(generator-capability): hand-written; no pack
  template emits an ExUnit formatter.

  ExUnit starts a formatter as a `GenServer` and casts it events; this one matches on plain
  maps (never `%ExUnit.Test{}`), so the library compiles without `:ex_unit` in
  `extra_applications`. `AshGraphLaw.Mutation.Runner` owns the table and reads it back.
  """

  use GenServer

  @table __MODULE__

  @doc "Creates the (single) result table owned by the calling process."
  @spec new_table() :: :ets.table()
  def new_table, do: :ets.new(@table, [:named_table, :public, :set])

  @doc "Names of the tests recorded as failed, sorted."
  @spec failed() :: [String.t()]
  def failed do
    @table |> :ets.tab2list() |> Enum.map(fn {name} -> name end) |> Enum.sort()
  end

  @doc "Drops the result table when it exists."
  @spec drop_table() :: :ok
  def drop_table do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    :ok
  end

  @impl GenServer
  def init(_config), do: {:ok, nil}

  @impl GenServer
  def handle_cast({:test_finished, %{state: {:failed, _}, name: name, module: module}}, state) do
    if :ets.whereis(@table) != :undefined, do: :ets.insert(@table, {"#{inspect(module)}: #{name}"})
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
