# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Law do
  @moduledoc """
  UNSUPPORTED(generator-capability): behaviour for modules that supply the GraphLaw payload of an admission.

  A law module turns a subject (changeset, query or action input) into `law` op step maps. The authoritative
  step format is `/Users/sac/graphlaw/tests/wasm_abi.rs` and `docs/refusals.md`. Steps use string keys.
  GraphLaw derives and validates; a law module never grants authority.
  """

  alias AshGraphLaw.Dsl.Admission

  @typedoc "Subject an admission runs against."
  @type subject :: Ash.Changeset.t() | Ash.Query.t() | Ash.ActionInput.t()

  @typedoc "Graph data handed to the engine."
  @type data :: %{text: String.t(), dialect: String.t()}

  @doc "Returns the step maps for the engine `law` op."
  @callback steps(subject(), %Admission{}) :: [map()]

  @doc "Optionally supplies graph data; `:default` selects the admission's projection."
  @callback data(subject(), %Admission{}) :: {:ok, data()} | :default

  @optional_callbacks data: 2

  @doc "Calls `module.data/2` when exported, otherwise returns `:default`."
  @spec data(module(), subject(), struct()) :: {:ok, data()} | :default
  def data(module, subject, admission) do
    if Code.ensure_loaded?(module) and function_exported?(module, :data, 2) do
      module.data(subject, admission)
    else
      :default
    end
  end
end
