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

  alias AshGraphLaw.Projection.Origin
  alias AshGraphLaw.Refusal

  @typedoc "Ash subject a projection observes."
  @type subject :: Ash.Changeset.t() | Ash.Query.t() | Ash.ActionInput.t()

  @typedoc "Projected graph: serialized RDF `text` and its `dialect` (for example `\"ntriples\"`)."
  @type data :: %{text: String.t(), dialect: String.t()}

  @doc """
  Projects `subject` into RDF text.

  Must be pure and deterministic: the same subject yields byte-identical `text`. Return
  `{:error, %AshGraphLaw.Refusal{code: :projection_failed}}` for a subject that cannot be
  projected. `opts` is reserved for projection-specific options and may be empty.
  """
  @callback data(subject :: subject(), opts :: keyword()) :: {:ok, data()} | {:error, Refusal.t()}

  @doc """
  Optional. Describes where the projected RDF came from as an `AshGraphLaw.Projection.Origin`.

  `subject` is the changeset, query or action input, or a bare resource module / record;
  `opts` may carry `:data` (the `t:data/0` already projected) and `:projection` (the module).
  Must be deterministic. When not implemented, `origin_for/3` builds a default origin.
  """
  @callback origin(subject :: term(), opts :: keyword()) :: Origin.t()

  @optional_callbacks origin: 2

  @doc """
  Returns the origin of `subject` as projected by `projection`.

  Calls the projection's optional `origin/2` callback when exported, otherwise builds the
  default origin (`AshGraphLaw.Projection.Default.origin/2`). `opts` is passed through with
  `:projection` set to `projection`.
  """
  @spec origin_for(module(), term(), keyword()) :: Origin.t()
  def origin_for(projection, subject, opts \\ []) when is_atom(projection) do
    opts = Keyword.put(opts, :projection, projection)
    Code.ensure_loaded(projection)

    if function_exported?(projection, :origin, 2) do
      projection.origin(subject, opts)
    else
      AshGraphLaw.Projection.Default.origin(subject, opts)
    end
  end

  @doc """
  Returns the sha256 hex digest of the projected text (the admission input digest).

  ## Examples

      iex> AshGraphLaw.Projection.input_digest(%{text: "", dialect: "ntriples"})
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  """
  @spec input_digest(data()) :: String.t()
  def input_digest(%{text: text}) when is_binary(text) do
    :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
  end
end
