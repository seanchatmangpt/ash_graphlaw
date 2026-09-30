# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Ash calculations, validations or changes

defmodule AshGraphLaw.Calculation.Conforms do
  @moduledoc """
  Boolean Ash calculation: does the record's projected graph conform to a SHACL shapes graph?

  UNSUPPORTED(generator-capability): hand-written; no pack template emits an Ash calculation.

  Exposes the typed `shacl` capability. The record is projected to RDF, the engine decides
  conformance, and the calculation returns `shacl.conforms`. Nothing here implements SHACL.

  ## Usage

      calculations do
        calculate :valid?, :boolean, {AshGraphLaw.Calculation.Conforms, shapes: @shapes}
      end

  ## Options

  | Option        | Type                  | Default                          | Meaning |
  |---------------|-----------------------|----------------------------------|---------|
  | `:shapes`     | non-empty string      | required                         | SHACL shapes graph (Turtle). |
  | `:projection` | module                | `AshGraphLaw.Projection.Default` | Projection override. |
  | `:server`     | atom or pid           | `AshGraphLaw.Pool`               | Engine server. |
  | `:timeout`    | positive integer (ms) | the resource's `timeout_ms`      | Per-call timeout. |
  | `:lease`      | term                  | none                             | Lease checked against the declared capability ceiling. |

  ## Refusals

  A record whose call is refused (`:capability_not_declared` when the resource declares
  capabilities without `shacl`, or any engine refusal) makes the whole calculation return
  `{:error, %AshGraphLaw.Error.Refused{}}`; the typed refusal is inside. Nothing is raised and no
  value is invented.

  ## Atomic behavior

  The calculation defines no `expression/2`: it needs an engine round trip per record, so it
  cannot be pushed into a data layer.
  """

  use Ash.Resource.Calculation

  alias AshGraphLaw.Lifecycle

  @allowed [:shapes, :projection, :server, :timeout, :lease]

  @doc "Validates the calculation options at compile time (`:shapes` is required)."
  @impl true
  @spec init(term()) :: {:ok, keyword()} | {:error, String.t()}
  def init(opts), do: Lifecycle.check_opts(opts, @allowed, [:shapes])

  @doc "Describes the calculation for error messages."
  @impl true
  @spec describe(keyword()) :: String.t()
  def describe(_opts), do: "GraphLaw SHACL conformance of the record's projected graph"

  @doc """
  Returns `{:ok, [boolean]}`, one entry per record in order, or the first
  `{:error, %AshGraphLaw.Error.Refused{}}`.
  """
  @impl true
  @spec calculate([Ash.Resource.record()], keyword(), map()) :: {:ok, [boolean()]} | {:error, Exception.t()}
  def calculate(records, opts, _context) do
    records
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, acc} ->
      case conforms(record, opts) do
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
  Decides one record: `{:ok, boolean}` or `{:error, %AshGraphLaw.Refusal{}}`.

  A `shacl` result whose `conforms` is not a boolean is a typed
  `:capability_response_undecodable` refusal.
  """
  @spec conforms(Ash.Resource.record(), keyword()) :: {:ok, boolean()} | {:error, AshGraphLaw.Refusal.t()}
  def conforms(record, opts) do
    subject = Lifecycle.subject(record)

    with {:ok, result} <- Lifecycle.run_on(subject, "shacl", [shapes: Keyword.fetch!(opts, :shapes)], opts) do
      case Map.get(result, :conforms) do
        value when is_boolean(value) -> {:ok, value}
        other -> {:error, Lifecycle.undecodable("shacl", other)}
      end
    end
  end
end
