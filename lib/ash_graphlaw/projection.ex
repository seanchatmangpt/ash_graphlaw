# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Projection do
  @moduledoc """
  Behaviour that projects an Ash subject into RDF text for GraphLaw admission.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits it.

  A projection turns a changeset, query or action input into
  `%{text: String.t(), dialect: String.t()}`. GraphLaw derives and validates over
  that text; it never authorizes. The projection is the only thing an admission
  observes, so it must be deterministic: the same subject yields byte-identical
  text. `AshGraphLaw.Projection.Default` is the reference implementation.
  """

  alias AshGraphLaw.Refusal

  @type subject :: Ash.Changeset.t() | Ash.Query.t() | Ash.ActionInput.t()
  @type data :: %{text: String.t(), dialect: String.t()}

  @callback data(subject :: subject(), opts :: keyword()) :: {:ok, data()} | {:error, Refusal.t()}

  @doc "Returns the sha256 hex digest of the projected text (the admission input digest)."
  @spec input_digest(data()) :: String.t()
  def input_digest(%{text: text}) when is_binary(text) do
    :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
  end
end
