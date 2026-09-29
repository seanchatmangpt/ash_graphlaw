# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Application do
  @moduledoc """
  OTP application callback. UNSUPPORTED(generator-capability): hand-written.

  Starts `AshGraphLaw.Pool` only when `config :ash_graphlaw, start_pool: true`
  (default `false`); otherwise the supervisor is empty, so depending on the
  library never loads or instantiates the WASM engine implicitly.

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

  @impl Application
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
