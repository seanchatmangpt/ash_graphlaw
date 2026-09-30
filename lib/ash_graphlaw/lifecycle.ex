# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Ash calculations, validations or changes

defmodule AshGraphLaw.Lifecycle do
  @moduledoc """
  Shared plumbing for the Ash lifecycle modules that expose typed GraphLaw capabilities.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits Ash calculations,
  validations or changes. The typed capability data path itself is generated; this module only
  wires an Ash subject to it.

  `AshGraphLaw.Calculation.Conforms`, `AshGraphLaw.Calculation.CanonicalId`,
  `AshGraphLaw.Calculation.Sparql`, `AshGraphLaw.Validation.Shacl` and
  `AshGraphLaw.Change.Canonicalize` all follow the same four steps:

    1. `subject/1` turns a record into a changeset the resource's projection can observe.
    2. `data_spec/2` projects the subject through the configured `AshGraphLaw.Projection`
       (`AshGraphLaw.Projection.Default` when none is configured) into a `data_spec`.
    3. `run/4` checks the resource may run the op (`AshGraphLaw.Authority.check_op/3`: a resource
       that declares capabilities may run only those, a resource that declares none may run all)
       and calls the op through `AshGraphLaw.Capability.API.run/3`.
    4. `to_error/1` folds a typed `AshGraphLaw.Refusal` into `AshGraphLaw.Error.Refused` so the Ash
       action fails with the refusal intact.

  This module never implements RDF, SPARQL or SHACL semantics: every decision is the engine's, and
  every failure is a returned `{:error, %AshGraphLaw.Refusal{}}`, never a raise and never dropped.

  ## Shared options

  | Option        | Type                  | Default                          | Meaning |
  |---------------|-----------------------|----------------------------------|---------|
  | `:projection` | module                | `AshGraphLaw.Projection.Default` | `AshGraphLaw.Projection` used to build the graph. |
  | `:server`     | atom or pid           | `AshGraphLaw.Pool`               | Engine server the call is sent to. |
  | `:timeout`    | positive integer (ms) | the resource's runtime `timeout_ms` | Per-call timeout. |
  | `:lease`      | term                  | none                             | Lease whose claimed ceiling is checked against the declared capability. |
  | `:lease_key`  | atom                  | `:graphlaw_lease`                | Changeset context key holding the lease (changeset-based modules). |

  Trust anchors and clocks are never read from these options.
  """

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Authority
  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Projection.Default, as: DefaultProjection
  alias AshGraphLaw.Refusal

  @default_lease_key :graphlaw_lease

  @typedoc ~S(A `data_spec` request value: `%{"text" => rdf_text, "dialect" => dialect}`.)
  @type data_spec :: %{required(String.t()) => String.t()}

  @doc "The default changeset context key holding a lease (`:graphlaw_lease`)."
  @spec default_lease_key() :: atom()
  def default_lease_key, do: @default_lease_key

  @doc """
  Validates lifecycle module options.

  `allowed` is the list of accepted keys and `required` the subset that must be present. Checks the
  shared option types (`:projection`, `:server`, `:timeout`, `:lease_key`) and the module-specific
  ones (`:shapes` and `:query` non-empty binaries, `:attribute` an atom).

  Returns `{:ok, opts}` (with `:lease_key` defaulted when allowed) or `{:error, message}`.
  """
  @spec check_opts(term(), [atom()], [atom()]) :: {:ok, keyword()} | {:error, String.t()}
  def check_opts(opts, allowed, required) when is_list(opts) do
    with :ok <- check_keyword(opts),
         :ok <- check_unknown(opts, allowed),
         :ok <- check_required(opts, required),
         :ok <- check_types(opts) do
      if :lease_key in allowed,
        do: {:ok, Keyword.put_new(opts, :lease_key, @default_lease_key)},
        else: {:ok, opts}
    end
  end

  def check_opts(_opts, _allowed, _required), do: {:error, "options must be a keyword list"}

  @doc """
  Returns a changeset whose projection observes `record`.

  A changeset is returned unchanged; a record (any struct with a resource module) becomes
  `Ash.Changeset.new/1`, so the projection sees its stored attribute values.
  """
  @spec subject(Ash.Changeset.t() | Ash.Resource.record()) :: Ash.Changeset.t()
  def subject(%Ash.Changeset{} = changeset), do: changeset
  def subject(%{__struct__: _resource} = record), do: Ash.Changeset.new(record)

  @doc """
  Projects `subject` into a `data_spec` with the configured projection.

  A projection returning anything other than `{:ok, %{text: text, dialect: dialect}}` or
  `{:error, %AshGraphLaw.Refusal{}}` is a typed `:projection_failed` refusal, as is a projection
  that raises.
  """
  @spec data_spec(AshGraphLaw.Projection.subject(), keyword()) :: {:ok, data_spec()} | {:error, Refusal.t()}
  def data_spec(subject, opts) do
    projection = Keyword.get(opts, :projection) || DefaultProjection

    case projection.data(subject, opts) do
      {:ok, %{text: text, dialect: dialect}} when is_binary(text) and is_binary(dialect) ->
        {:ok, %{"text" => text, "dialect" => dialect}}

      {:error, %Refusal{} = refusal} ->
        {:error, refusal}

      other ->
        {:error,
         Refusal.new(:projection_failed, "projection returned an unexpected value", %{returned: inspect(other)})}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(:projection_failed, Exception.message(exception), %{exception: inspect(exception.__struct__)})}
  end

  @doc """
  The engine options a lifecycle call sends: `:server` and `:timeout` only.

  `:timeout` falls back to the resource's runtime `timeout_ms`. Lease fields are ordinary request
  arguments of the typed op and are never smuggled through these options.
  """
  @spec engine_opts(module(), keyword()) :: keyword()
  def engine_opts(resource, opts) do
    [
      server: opts[:server] || AshGraphLaw.Pool,
      timeout: opts[:timeout] || Admissions.runtime(resource).timeout_ms
    ]
  end

  @doc """
  Runs typed op `op` for `resource` with request `args`.

  Checks `AshGraphLaw.Authority.check_op/3` first (a `:capability_not_declared` or `:ceiling_unmet`
  refusal is returned before the engine is called), then calls
  `AshGraphLaw.Capability.API.run/3`. The result is the typed op result or the typed refusal.
  """
  @spec run(module(), String.t(), keyword() | map(), keyword()) :: {:ok, term()} | {:error, Refusal.t()}
  def run(resource, op, args, opts) when is_atom(resource) and is_binary(op) do
    with :ok <- Authority.check_op(resource, op, policy(opts)) do
      AshGraphLaw.Capability.API.run(op, args, engine_opts(resource, opts))
    end
  end

  @doc """
  Projects `subject` and runs typed op `op` over it.

  `extra` are the op's remaining request arguments; `data` is filled from the projection. The
  subject's resource must be a module (a changeset always has one).
  """
  @spec run_on(Ash.Changeset.t(), String.t(), keyword(), keyword()) :: {:ok, term()} | {:error, Refusal.t()}
  def run_on(%Ash.Changeset{resource: resource} = subject, op, extra, opts) do
    with {:ok, data} <- data_spec(subject, opts) do
      run(resource, op, [{:data, data} | extra], opts)
    end
  end

  @doc "The lease presented for `changeset`: `opts[:lease]`, else `changeset.context[lease_key]`."
  @spec lease(Ash.Changeset.t(), keyword()) :: term()
  def lease(%Ash.Changeset{context: context}, opts) do
    case Keyword.get(opts, :lease) do
      nil -> Map.get(context, Keyword.get(opts, :lease_key, @default_lease_key))
      lease -> lease
    end
  end

  @doc "Wraps a typed refusal as an `AshGraphLaw.Error.Refused` Ash error."
  @spec to_error(Refusal.t()) :: Refused.t()
  def to_error(%Refusal{} = refusal), do: Refused.exception(refusal: refusal)

  @doc """
  The refusal for an engine response that decoded but is not the shape the lifecycle module needs
  (for example `shacl` without a boolean `conforms`). The undecodable value is kept in `details`.
  """
  @spec undecodable(String.t(), term()) :: Refusal.t()
  def undecodable(op, value) do
    Refusal.new(:capability_response_undecodable, "#{op} response is not usable by the lifecycle module", %{
      op: op,
      value: inspect(value, limit: 20, printable_limit: 200)
    })
  end

  defp policy(opts) do
    case Keyword.get(opts, :lease) do
      nil -> []
      lease -> [lease: lease]
    end
  end

  defp check_keyword(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, "options must be a keyword list"}
  end

  defp check_unknown(opts, allowed) do
    case Keyword.keys(opts) -- allowed do
      [] -> :ok
      unknown -> {:error, "unknown options: #{inspect(Enum.uniq(unknown))}; allowed: #{inspect(allowed)}"}
    end
  end

  defp check_required(opts, required) do
    case Enum.reject(required, &Keyword.has_key?(opts, &1)) do
      [] -> :ok
      missing -> {:error, "missing required options: #{inspect(missing)}"}
    end
  end

  defp check_types(opts) do
    Enum.find_value(opts, :ok, fn {key, value} ->
      if valid?(key, value), do: nil, else: {:error, "invalid #{inspect(key)}: #{inspect(value)}"}
    end)
  end

  defp valid?(:projection, value), do: is_atom(value)
  defp valid?(:server, value), do: is_atom(value) or is_pid(value)
  defp valid?(:timeout, value), do: is_nil(value) or (is_integer(value) and value > 0)
  defp valid?(:lease_key, value), do: is_atom(value) and not is_nil(value)
  defp valid?(:attribute, value), do: is_atom(value) and not is_nil(value)
  defp valid?(key, value) when key in [:shapes, :query, :base], do: is_binary(value) and value != ""
  defp valid?(:terms, value), do: value in [:values, :raw]
  defp valid?(:message, value), do: is_binary(value)
  defp valid?(_key, _value), do: true
end
