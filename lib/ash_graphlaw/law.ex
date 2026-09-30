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

  @typedoc "Graph data handed to the engine: serialized RDF `text` and its `dialect` (for example `\"ntriples\"`)."
  @type data :: %{text: String.t(), dialect: String.t()}

  @doc """
  Returns the step maps (string keys) for the engine `law` op.

  Called once per admission run with the subject and the declared admission. Must be
  deterministic in its arguments and must not perform side effects; a raise is turned into a
  typed `:law_module_failed` refusal. Declared steps that need a payload (see
  `AshGraphLaw.Contract.payload_steps/0`) require a law module exporting this callback.
  """
  @callback steps(subject(), %Admission{}) :: [map()]

  @doc """
  Optionally supplies graph data; `:default` selects the admission's projection.

  Return `{:ok, %{text: text, dialect: dialect}}` to replace the projected graph for this
  admission, or `:default` to fall back to `AshGraphLaw.Projection.Default`.
  """
  @callback data(subject(), %Admission{}) :: {:ok, data()} | :default

  @optional_callbacks data: 2

  @doc """
  Calls `module.data/2` when exported, otherwise returns `:default`.

  `data/2` is an optional callback, so a law module that only defines `steps/2` uses the
  admission's default projection.
  """
  @spec data(module(), subject(), struct()) :: {:ok, data()} | :default
  def data(module, subject, admission) do
    if Code.ensure_loaded?(module) and function_exported?(module, :data, 2) do
      module.data(subject, admission)
    else
      :default
    end
  end
end
