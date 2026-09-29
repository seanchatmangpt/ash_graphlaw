# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Standing do
  @moduledoc """
  Closed standing vocabulary, generated from the ontology (`queries/standing.rq`).

  Standing is derived from a result and is bound to the exact input digest that
  produced it. It is never stored on the DSL and never carried between inputs.
  `of/1` maps:

    * `{:ok, %AshGraphLaw.Admitted{}}` to `:PARTIAL_ALIVE` (admission observed on the
      exact input, consequence not executed; never `:ALIVE`)
    * `{:error, %AshGraphLaw.Refusal{class: :blocked_resource}}` to `:BLOCKED`
    * `{:error, %AshGraphLaw.Refusal{class: :unsupported}}` to `:UNSUPPORTED`
    * any other refusal and anything else to `:UNKNOWN` (the typed refusal itself
      carries REFUSED)

  Nothing here authorizes anything.
  """

  alias AshGraphLaw.{Admitted, Refusal}

  @standings [
    :UNKNOWN,
    :PARTIAL_ALIVE,
    :ALIVE,
    :BLOCKED,
    :BUILD_BROKEN,
    :UNSUPPORTED
  ]

  @type t ::
          :UNKNOWN
          | :PARTIAL_ALIVE
          | :ALIVE
          | :BLOCKED
          | :BUILD_BROKEN
          | :UNSUPPORTED

  for required <- [:UNKNOWN, :PARTIAL_ALIVE, :BLOCKED, :UNSUPPORTED] do
    unless required in @standings do
      raise CompileError, description: "standing #{inspect(required)} missing from generated vocabulary"
    end
  end

  @doc "All standings, in ontology order."
  @spec all() :: [t()]
  def all, do: @standings

  @doc "True when `value` is a member of the closed vocabulary."
  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @standings

  @doc "Ontology definition of a standing (string)."
  @spec describe(t()) :: String.t()
  def describe(:UNKNOWN),
    do: ~S"""
    No observation binds this subject yet; not admitted, not refused.
    """

  def describe(:PARTIAL_ALIVE),
    do: ~S"""
    Admission was observed on the exact input digest; the consequence was not executed.
    """

  def describe(:ALIVE),
    do: ~S"""
    The exact admitted subject was observed executing. This library never assigns it from admission alone.
    """

  def describe(:BLOCKED),
    do: ~S"""
    A resource blocked the decision (missing WASM, timeout, saturation); nothing was decided.
    """

  def describe(:BUILD_BROKEN),
    do: ~S"""
    The subject does not build, so no admission can be observed on it.
    """

  def describe(:UNSUPPORTED),
    do: ~S"""
    The requested step or engine variant is outside what this library version supports.
    """

  @doc "Derives standing from a result of `AshGraphLaw.law/3` or `AshGraphLaw.call/2`."
  @spec of(term()) :: t()
  def of({:ok, %Admitted{}}), do: :PARTIAL_ALIVE
  def of({:error, %Refusal{class: :blocked_resource}}), do: :BLOCKED
  def of({:error, %Refusal{class: :unsupported}}), do: :UNSUPPORTED
  def of({:error, %Refusal{}}), do: :UNKNOWN
  def of(_other), do: :UNKNOWN
end
