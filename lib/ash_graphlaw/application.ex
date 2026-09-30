# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
# UNSUPPORTED(generator-capability): hand-written residue; no pack emits this module.
# Recorded in HANDWRITTEN.md. Do not regenerate over it.

defmodule AshGraphLaw.Application do
  @moduledoc """
  OTP application callback. UNSUPPORTED(generator-capability): hand-written.

  Starts `AshGraphLaw.Pool` only when `config :ash_graphlaw, start_pool: true`
  (default `false`); otherwise the supervisor is empty, so depending on the
  library never loads or instantiates the WASM engine implicitly.

  ## Usage

      # config/config.exs
      config :ash_graphlaw, start_pool: true, pool: [size: 4, timeout_ms: 5_000]

  ## Options

  `:start_pool` (boolean, default `false`) and `:pool` (keyword list handed to
  `AshGraphLaw.Pool.start_link/1`; any non-list value is treated as `[]`).

  ## Supervision tree

  `AshGraphLaw.Supervisor` (`:one_for_one`, registered by name) has either no
  children (`start_pool: false`) or one child, `AshGraphLaw.Pool`, which itself
  supervises `AshGraphLaw.Pool.Registry` and the `AshGraphLaw.Host` members.
  `children/0` is public so both branches can be asserted without starting the
  application.

  ## Telemetry

  None emitted here. See `AshGraphLaw.Host` and `AshGraphLaw.EngineLoad`.

  ## Failure modes

  `start/2` never loads the engine itself; a missing or foreign engine surfaces
  as a typed refusal from each `AshGraphLaw.Host` call, not as a boot failure.

  ## See Also

  `AshGraphLaw.Pool`, `AshGraphLaw.Host`, `AshGraphLaw.WasmConfig`.

  GraphLaw derives and validates; nothing here authorizes or actuates.
  """

  use Application

  @doc "Children started under `AshGraphLaw.Supervisor` for the current config."
  @spec children() :: [Supervisor.child_spec() | module() | {module(), term()}]
  def children do
    if Application.get_env(:ash_graphlaw, :start_pool, false) do
      [{AshGraphLaw.Pool, pool_opts()}]
    else
      []
    end
  end

  @doc "Starts `AshGraphLaw.Supervisor` with the children from `children/0`."
  @impl Application
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: AshGraphLaw.Supervisor)
  end

  defp pool_opts do
    case Application.get_env(:ash_graphlaw, :pool, []) do
      opts when is_list(opts) -> opts
      _ -> []
    end
  end
end
