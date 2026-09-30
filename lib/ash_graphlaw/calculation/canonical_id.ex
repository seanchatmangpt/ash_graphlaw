# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Ash calculations, validations or changes

defmodule AshGraphLaw.Calculation.CanonicalId do
  @moduledoc """
  Ash calculation returning the canonical identity of the record's projected graph.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits an Ash calculation.

  Exposes the typed `canonical` capability: the engine canonicalizes the projected RDF and
  returns its `"sha256:..."` id. Equal graphs (up to blank node labelling and statement order)
  have equal ids. Note that the identity covers exactly what the projection emits: the default
  projection includes the primary key in the subject IRI, so use a projection without it when the
  id must depend on attribute values only.

  ## Usage

      calculations do
        calculate :graph_id, :string, AshGraphLaw.Calculation.CanonicalId
        calculate :graph_id, :string, {AshGraphLaw.Calculation.CanonicalId, projection: MyProjection}
      end

  ## Options

  | Option        | Type                  | Default                          | Meaning |
  |---------------|-----------------------|----------------------------------|---------|
  | `:projection` | module                | `AshGraphLaw.Projection.Default` | Projection override. |
  | `:server`     | atom or pid           | `AshGraphLaw.Pool`               | Engine server. |
  | `:timeout`    | positive integer (ms) | the resource's `timeout_ms`      | Per-call timeout. |
  | `:lease`      | term                  | none                             | Lease checked against the declared capability ceiling. |

  ## Refusals

  Any refusal (undeclared capability, engine refusal, unusable response) makes the calculation
  return `{:error, %AshGraphLaw.Error.Refused{}}` carrying the typed refusal.
  """

  use Ash.Resource.Calculation

  alias AshGraphLaw.Lifecycle

  @allowed [:projection, :server, :timeout, :lease]

  @doc "Validates the calculation options at compile time."
  @impl true
  @spec init(term()) :: {:ok, keyword()} | {:error, String.t()}
  def init(opts), do: Lifecycle.check_opts(opts, @allowed, [])

  @doc "Describes the calculation for error messages."
  @impl true
  @spec describe(keyword()) :: String.t()
  def describe(_opts), do: "GraphLaw canonical id of the record's projected graph"

  @doc """
  Returns `{:ok, [id]}`, one `"sha256:..."` string per record in order, or the first
  `{:error, %AshGraphLaw.Error.Refused{}}`.
  """
  @impl true
  @spec calculate([Ash.Resource.record()], keyword(), map()) :: {:ok, [String.t()]} | {:error, Exception.t()}
  def calculate(records, opts, _context) do
    records
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, acc} ->
      case canonical_id(record, opts) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        {:error, refusal} -> {:halt, {:error, Lifecycle.to_error(refusal)}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  @doc """
  Canonical id of one record: `{:ok, "sha256:..."}` or `{:error, %AshGraphLaw.Refusal{}}`.

  A `canonical` result whose `id` is not a binary is a typed `:capability_response_undecodable`
  refusal.
  """
  @spec canonical_id(Ash.Resource.record() | Ash.Changeset.t(), keyword()) ::
          {:ok, String.t()} | {:error, AshGraphLaw.Refusal.t()}
  def canonical_id(subject, opts) do
    with {:ok, result} <- subject |> Lifecycle.subject() |> Lifecycle.run_on("canonical", [], opts) do
      case Map.get(result, :id) do
        id when is_binary(id) -> {:ok, id}
        other -> {:error, Lifecycle.undecodable("canonical", other)}
      end
    end
  end
end
