# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
# UNSUPPORTED(generator-capability): hand-written residue; no pack emits this module.
# Recorded in HANDWRITTEN.md. Do not regenerate over it.

defmodule AshGraphLaw.Pool do
  @moduledoc """
  N supervised `AshGraphLaw.Host` instances behind one name.
  UNSUPPORTED(generator-capability): hand-written.

  A single host serializes every `gl_alloc`/`gl_call`/`gl_free` transaction, so
  one host caps throughput at one core. This supervisor starts `:size` hosts
  (default `System.schedulers_online/0`). Member 0 keeps the registered name
  `AshGraphLaw.Host`; every member joins a duplicate-key
  `AshGraphLaw.Pool.Registry` under `:members` while it has a live engine
  instance, and `request/2` routes to the member with the shortest mailbox
  (`pick/1`). A member whose engine is unavailable (failed load or recycle)
  leaves `:members` and joins `:unavailable` until it heals, so a dead member
  with an always-empty mailbox can never win the routing. When no member is
  live, `request/2` forwards to an unavailable one so the caller receives that
  member's real typed refusal instead of an opaque error.

  Routing by mailbox length is best-effort: the length is read before the call
  is enqueued, so concurrent callers can read the same lengths. Ties (and so a
  simultaneous burst reading equal lengths) are broken at random, which spreads
  the burst across the members instead of piling it on one. It balances load; it
  does not guarantee a bound (each host still sheds past its own `:max_queue`).

  The strategy is `:rest_for_one`: the registry is the first child and every
  member registers from `init/1`. A registry crash drops all registrations, so
  the members started after it restart and re-register.

  ## Usage

      {:ok, _pid} = AshGraphLaw.Pool.start_link(size: 2)
      {:ok, response} = AshGraphLaw.Pool.request(%{"op" => "capabilities"})

  ## Options

  See `t:opts/0`: `:name`, `:size`, and every `AshGraphLaw.Host` option.

  ## Telemetry

  The pool emits none. Members emit the `AshGraphLaw.Host` events
  (`[:ash_graphlaw, :host, :call, :stop]`, `[:ash_graphlaw, :host, :recycle]`).

  ## Failure modes

  `:host_not_started` when no member is registered (live or unavailable);
  otherwise the chosen member's own typed `AshGraphLaw.Refusal`
  (for example `:saturated`, `:wasm_not_vendored`, `:call_timeout`).

  ## See Also

  `AshGraphLaw.Host`, `AshGraphLaw.Application`, `AshGraphLaw.WasmConfig`.

  GraphLaw derives and validates; nothing here authorizes or actuates.
  """

  use Supervisor

  alias AshGraphLaw.Refusal

  @registry AshGraphLaw.Pool.Registry
  @host AshGraphLaw.Host

  @typedoc "Pool options: `:name`, `:size`, plus any `AshGraphLaw.Host` option."
  @type opts :: [
          {:name, atom()}
          | {:size, pos_integer()}
          | {:wasm_path, String.t()}
          | {:bytes, binary()}
          | {:expected_sha256, String.t() | :unpinned}
          | {atom(), term()}
        ]

  @doc "The registry the pool's members join (under the key `:members`)."
  @spec registry() :: atom()
  def registry, do: @registry

  @doc """
  Starts the pool. Options: `:name` (supervisor name, default this module),
  `:size` (default `System.schedulers_online/0`), and any `AshGraphLaw.Host`
  option, passed to every member.
  """
  @spec start_link(opts()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  @impl Supervisor
  @spec init(opts()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(opts) do
    n = size(opts)
    host_opts = Keyword.drop(opts, [:size, :registry, :name])

    members =
      for i <- 0..(n - 1)//1 do
        name = if i == 0, do: @host, else: nil

        Supervisor.child_spec(
          {@host, Keyword.merge(host_opts, name: name, registry: @registry)},
          id: {@host, i}
        )
      end

    Supervisor.init([{Registry, keys: :duplicate, name: @registry} | members], strategy: :rest_for_one)
  end

  @doc "Pool size resolved from `opts[:size]`, then the scheduler count."
  @spec size(opts()) :: pos_integer()
  def size(opts \\ []) do
    case Keyword.get(opts, :size) do
      n when is_integer(n) and n > 0 -> n
      _ -> System.schedulers_online()
    end
  end

  @doc """
  Routes `request` to the member with the shortest mailbox via
  `AshGraphLaw.Host.request/3`. With no live member, returns a
  `:host_not_started` refusal.
  """
  @spec request(map(), keyword()) :: {:ok, map()} | {:error, Refusal.t()}
  def request(request, opts \\ []) when is_map(request) do
    case pick() || List.first(unavailable_members()) do
      nil ->
        {:error, Refusal.new(:host_not_started, "no AshGraphLaw.Host member is registered in the pool")}

      pid ->
        AshGraphLaw.Host.request(pid, request, opts)
    end
  end

  @doc """
  Engine identity of the pool: `AshGraphLaw.Host.info/2` of the first live member
  (`{:ok, %{wasm_sha256: _, ...}}`), or a typed refusal when no member is live.
  """
  @spec info(atom()) :: {:ok, map()} | {:error, Refusal.t()}
  def info(registry \\ @registry) do
    case registry |> members() |> Enum.sort() |> List.first() do
      nil -> {:error, Refusal.new(:host_not_started, "no live AshGraphLaw.Host member is registered in the pool")}
      pid -> AshGraphLaw.Host.info(pid)
    end
  end

  @doc "The live member with the shortest mailbox, or `nil` when none is routable."
  @spec pick(atom()) :: pid() | nil
  def pick(registry \\ @registry) do
    # Shuffled first: a burst of callers reads the same (often all-zero) mailbox lengths, and
    # `Enum.min_by/3` would send every one of them to the first member of the list.
    registry
    |> members()
    |> Enum.shuffle()
    |> Enum.map(fn pid -> {queue_len(pid), pid} end)
    |> Enum.reject(fn {len, _pid} -> is_nil(len) end)
    |> Enum.min_by(&elem(&1, 0), fn -> {nil, nil} end)
    |> elem(1)
  end

  @doc "Every live member pid."
  @spec members(atom()) :: [pid()]
  def members(registry \\ @registry), do: registered(registry, :members)

  @doc "Every member pid whose engine is currently unavailable (still supervised, retrying)."
  @spec unavailable_members(atom()) :: [pid()]
  def unavailable_members(registry \\ @registry), do: registered(registry, :unavailable)

  defp registered(registry, key) do
    if Process.whereis(registry),
      do: registry |> Registry.lookup(key) |> Enum.map(&elem(&1, 0)),
      else: []
  rescue
    # A registry mid-restart has its name registered before its key table
    # exists; `Registry.lookup/2` raises. No member is routable in that window.
    ArgumentError -> []
  end

  defp queue_len(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      nil -> nil
    end
  end
end
