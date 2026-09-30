# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Ash calculations, validations or changes

defmodule AshGraphLaw.Validation.Shacl.NonConformance do
  @moduledoc """
  Splode error (class `:invalid`) for a changeset whose projected graph does not conform to the
  SHACL shapes graph.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits a Splode error module.

  Carries the engine's SHACL `:results` (plain string-keyed maps, lossless) and the `:resource`
  module. It is a validation outcome, not a refusal: the engine decided normally. A refused call is
  `AshGraphLaw.Error.Refused` instead.
  """

  use Splode.Error, fields: [:results, :resource, :detail], class: :invalid

  @type t :: %__MODULE__{results: [map()] | nil, resource: module() | nil, detail: String.t() | nil}

  @doc "Human-readable message: the configured detail, or the count of SHACL violations."
  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{detail: detail}) when is_binary(detail) and detail != "", do: detail

  def message(%__MODULE__{results: results}) when is_list(results),
    do: "GraphLaw SHACL non-conformance: #{length(results)} result(s)"

  def message(%__MODULE__{}), do: "GraphLaw SHACL non-conformance"
end

defmodule AshGraphLaw.Validation.Shacl do
  @moduledoc """
  Ash validation: the changeset's projected graph must conform to a SHACL shapes graph.

  UNSUPPORTED(generator-capability): hand-written; Ash validations are outside every listed pack.

  Exposes the typed `shacl` capability. The changeset is projected to RDF, the engine decides
  conformance and lists the SHACL results; this module only turns the verdict into an Ash error.

  ## Usage

      validations do
        validate {AshGraphLaw.Validation.Shacl, shapes: @shapes}
      end

  ## Options

  | Option        | Type                  | Default                          | Meaning |
  |---------------|-----------------------|----------------------------------|---------|
  | `:shapes`     | non-empty string      | required                         | SHACL shapes graph (Turtle). |
  | `:projection` | module                | `AshGraphLaw.Projection.Default` | Projection override. |
  | `:server`     | atom or pid           | `AshGraphLaw.Pool`               | Engine server. |
  | `:timeout`    | positive integer (ms) | the resource's `timeout_ms`      | Per-call timeout. |
  | `:lease`      | term                  | none                             | Lease checked against the declared capability ceiling. |
  | `:lease_key`  | atom                  | `:graphlaw_lease`                | Changeset context key holding the lease. |
  | `:message`    | string                | none                             | Error message replacing the default. |

  ## Errors

    * non-conformance: `AshGraphLaw.Validation.Shacl.NonConformance` carrying the SHACL results;
    * a refused call (`:capability_not_declared`, engine refusal, unusable response):
      `AshGraphLaw.Error.Refused` carrying the typed refusal. Never raised, never swallowed.

  ## Atomic behavior

  `atomic/3` returns `{:not_atomic, "GraphLaw SHACL validation requires a WASM call"}`: the check
  needs an engine round trip per record, so Ash uses the non-atomic path.

  ## Authority

  A conforming verdict is an observation of one projected input, not a grant of authority.
  """

  use Ash.Resource.Validation

  alias AshGraphLaw.Lifecycle
  alias AshGraphLaw.Validation.Shacl.NonConformance

  @allowed [:shapes, :projection, :server, :timeout, :lease, :lease_key, :message]

  @doc "Validates and normalizes the options (`:shapes` is required; `:lease_key` is defaulted)."
  @impl Ash.Resource.Validation
  @spec init(keyword()) :: {:ok, keyword()} | {:error, String.t()}
  def init(opts), do: Lifecycle.check_opts(opts, @allowed, [:shapes])

  @doc "Returns the subjects this validation supports: `Ash.Changeset`."
  @impl Ash.Resource.Validation
  @spec supports(keyword()) :: [module()]
  def supports(_opts), do: [Ash.Changeset]

  @doc """
  Returns `:ok` when the engine reports conformance, `{:error, %NonConformance{}}` with the SHACL
  results otherwise, or `{:error, %AshGraphLaw.Error.Refused{}}` when the call is refused.
  """
  @impl Ash.Resource.Validation
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.context()) :: :ok | {:error, Exception.t()}
  def validate(%Ash.Changeset{resource: resource} = changeset, opts, _context) do
    opts = Keyword.put(opts, :lease, Lifecycle.lease(changeset, opts))
    extra = [shapes: Keyword.fetch!(opts, :shapes)]

    case Lifecycle.run_on(changeset, "shacl", extra, opts) do
      {:ok, result} -> verdict(result, resource, opts)
      {:error, refusal} -> {:error, Lifecycle.to_error(refusal)}
    end
  end

  @doc "Declares the validation non-atomic."
  @impl Ash.Resource.Validation
  @spec atomic(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.context()) :: {:not_atomic, String.t()}
  def atomic(_changeset, _opts, _context), do: {:not_atomic, "GraphLaw SHACL validation requires a WASM call"}

  @doc "Describes the validation for error messages (`message` and `vars`)."
  @impl Ash.Resource.Validation
  @spec describe(keyword()) :: [message: String.t(), vars: keyword()]
  def describe(_opts), do: [message: "must conform to the SHACL shapes graph", vars: []]

  defp verdict(result, resource, opts) do
    case Map.get(result, :conforms) do
      true ->
        :ok

      false ->
        {:error,
         NonConformance.exception(
           results: results(result),
           resource: resource,
           detail: Keyword.get(opts, :message)
         )}

      other ->
        {:error, "shacl" |> Lifecycle.undecodable(other) |> Lifecycle.to_error()}
    end
  end

  defp results(result) do
    case Map.get(result, :results) do
      results when is_list(results) -> results
      _other -> []
    end
  end
end
