# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Ash calculations, validations or changes

defmodule AshGraphLaw.Calculation.Sparql do
  @moduledoc """
  Ash calculation running a SPARQL query over the record's projected graph.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits an Ash calculation.

  Exposes the typed `sparql` capability; the engine evaluates the query. The value depends on the
  result kind the engine reports:

    * `:solutions` - a list of row maps, `%{variable => value}` (one map per solution row);
    * `:graph` - the N-Quads text of the constructed graph;
    * `:boolean` - the ASK answer.

  With `terms: :values` (default) each row value is the term's lexical value; with `terms: :raw`
  each value is the engine term as decoded (`AshGraphLaw.Result.Term`, or the raw term map).

  ## Usage

      calculations do
        calculate :titles, {:array, :map},
          {AshGraphLaw.Calculation.Sparql, query: "SELECT ?t WHERE { ?s ?p ?t }"}
      end

  ## Options

  | Option        | Type                  | Default                          | Meaning |
  |---------------|-----------------------|----------------------------------|---------|
  | `:query`      | non-empty string      | required                         | SPARQL query. |
  | `:base`       | non-empty string      | none                             | Base IRI for the data. |
  | `:terms`      | `:values` or `:raw`   | `:values`                        | Row value shape. |
  | `:projection` | module                | `AshGraphLaw.Projection.Default` | Projection override. |
  | `:server`     | atom or pid           | `AshGraphLaw.Pool`               | Engine server. |
  | `:timeout`    | positive integer (ms) | the resource's `timeout_ms`      | Per-call timeout. |
  | `:lease`      | term                  | none                             | Lease checked against the declared capability ceiling. |

  ## Refusals

  Any refusal (undeclared capability, engine rejection of the query, an unknown result kind) makes
  the calculation return `{:error, %AshGraphLaw.Error.Refused{}}` carrying the typed refusal.
  """

  use Ash.Resource.Calculation

  alias AshGraphLaw.Lifecycle

  @allowed [:query, :base, :terms, :projection, :server, :timeout, :lease]

  @doc "Validates the calculation options at compile time (`:query` is required)."
  @impl true
  @spec init(term()) :: {:ok, keyword()} | {:error, String.t()}
  def init(opts), do: Lifecycle.check_opts(opts, @allowed, [:query])

  @doc "Describes the calculation for error messages."
  @impl true
  @spec describe(keyword()) :: String.t()
  def describe(opts), do: "GraphLaw SPARQL over the record's projected graph: #{Keyword.get(opts, :query)}"

  @doc """
  Returns `{:ok, [value]}`, one entry per record in order, or the first
  `{:error, %AshGraphLaw.Error.Refused{}}`.
  """
  @impl true
  @spec calculate([Ash.Resource.record()], keyword(), map()) :: {:ok, [term()]} | {:error, Exception.t()}
  def calculate(records, opts, _context) do
    records
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, acc} ->
      case query(record, opts) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, refusal} -> {:halt, {:error, Lifecycle.to_error(refusal)}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  @doc """
  Runs the query for one record: `{:ok, rows | nquads | boolean}` or
  `{:error, %AshGraphLaw.Refusal{}}`.
  """
  @spec query(Ash.Resource.record() | Ash.Changeset.t(), keyword()) ::
          {:ok, [map()] | String.t() | boolean()} | {:error, AshGraphLaw.Refusal.t()}
  def query(subject, opts) do
    extra = [query: Keyword.fetch!(opts, :query)] ++ base(opts)

    with {:ok, result} <- subject |> Lifecycle.subject() |> Lifecycle.run_on("sparql", extra, opts) do
      shape(result, Keyword.get(opts, :terms, :values))
    end
  end

  defp base(opts) do
    case Keyword.get(opts, :base) do
      nil -> []
      base -> [base: base]
    end
  end

  defp shape(%{kind: :solutions, variables: variables, rows: rows}, terms)
       when is_list(variables) and is_list(rows) do
    rows
    |> Enum.reduce_while({:ok, []}, fn
      row, {:ok, acc} when is_list(row) ->
        {:cont, {:ok, [variables |> Enum.zip(Enum.map(row, &term(&1, terms))) |> Map.new() | acc]}}

      row, _acc ->
        {:halt, {:error, Lifecycle.undecodable("sparql", row)}}
    end)
    |> case do
      {:ok, shaped} -> {:ok, Enum.reverse(shaped)}
      error -> error
    end
  end

  defp shape(%{kind: :graph, nquads: nquads}, _terms) when is_binary(nquads), do: {:ok, nquads}
  defp shape(%{kind: :boolean, value: value}, _terms) when is_boolean(value), do: {:ok, value}

  defp shape(%{kind: kind} = result, _terms),
    do: {:error, Lifecycle.undecodable("sparql", {kind, Map.get(result, :raw)})}

  defp shape(other, _terms), do: {:error, Lifecycle.undecodable("sparql", other)}

  defp term(term, :raw), do: term
  defp term(%{value: value}, :values), do: value
  defp term(%{"value" => value}, :values), do: value
  defp term(other, :values), do: other
end
