# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Error.Refused do
  @moduledoc """
  Splode error (class `:invalid`) wrapping an `AshGraphLaw.Refusal`.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits a Splode error module.

  Adding this error to a changeset, query or action input makes the Ash action
  fail while keeping the typed refusal intact: recover it after
  `Ash.Error.to_error_class/1` with `AshGraphLaw.Error.refusals/1`.
  """

  use Splode.Error, fields: [:refusal], class: :invalid

  alias AshGraphLaw.Refusal

  @type t :: %__MODULE__{refusal: Refusal.t() | nil}

  @doc """
  The refusal code (for example `:not_admitted`), or `nil` when no refusal is attached.

  The `nil` fallback clause covers an error struct built without a `%Refusal{}`.
  """
  @spec code(t()) :: atom() | nil
  def code(%__MODULE__{refusal: %Refusal{code: code}}), do: code
  def code(%__MODULE__{}), do: nil

  @doc """
  The whole engine error map the refusal was decoded from (lossless), or `nil` for a
  client-side refusal or an error struct built without a `%Refusal{}`.
  """
  @spec raw(t()) :: map() | nil
  def raw(%__MODULE__{refusal: %Refusal{} = refusal}), do: Map.get(refusal, :raw)
  def raw(%__MODULE__{}), do: nil

  @doc """
  The Chatman failure-taxonomy term of the refusal, or `nil`.

  The `nil` fallback clause covers an error struct built without a `%Refusal{}`.
  """
  @spec broken_term(t()) :: atom() | nil
  def broken_term(%__MODULE__{refusal: %Refusal{broken_term: term}}), do: term
  def broken_term(%__MODULE__{}), do: nil

  @doc """
  Human-readable message: `"GraphLaw refused: <code>"`.

  The fallback clause (no refusal attached, or a `nil` refusal) yields
  `"GraphLaw refused: unknown"` instead of raising, so an error built without a refusal still
  renders.
  """
  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{refusal: %Refusal{code: code}}), do: "GraphLaw refused: #{code}"
  def message(%__MODULE__{}), do: "GraphLaw refused: unknown"
end
