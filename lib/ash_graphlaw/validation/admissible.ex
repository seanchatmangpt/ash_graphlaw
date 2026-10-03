# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Validation.Admissible do
  @moduledoc """
  Pass/fail Ash validation that runs a declared GraphLaw admission.

  UNSUPPORTED(generator-capability): hand-written; Ash validations are outside every listed pack.

  ## Usage

      validations do
        validate {AshGraphLaw.Validation.Admissible, admission: :ticket_shape}
      end

  Supports `Ash.Changeset` and `Ash.ActionInput`. No evidence is recorded; use
  `AshGraphLaw.Change.Admit` to keep an `AshGraphLaw.Evidence` in the changeset context.

  ## Options

  See `t:opts/0`.

  | Option        | Type            | Default                                | Meaning |
  |---------------|-----------------|----------------------------------------|---------|
  | `:admission`  | atom (required) | none                                   | Declared admission name. |
  | `:projection` | module or `nil` | admission's `projection`, then `AshGraphLaw.Projection.Default` | Projection override. |
  | `:server`     | atom            | `AshGraphLaw.Pool`                     | Pool/host server name. |
  | `:timeout`    | positive integer (ms) | runtime `timeout_ms`             | Per-call timeout. |
  | `:lease_key`  | atom            | `:graphlaw_lease`                      | Context key holding the lease. |

  `init/1` normalizes `:lease_key` to `:graphlaw_lease` and `:projection` to `nil` when absent.

  ## Lease context key

  The lease is read from the subject's `context[lease_key]`. Only a `:signed_lease` entry can raise
  the ceiling above `:observe`; the engine verifies it against `runtime.trusted_keys`. See
  `AshGraphLaw.Authority`.

  ## Refusals

  Failures are `AshGraphLaw.Error.Refused` errors that carry the typed `AshGraphLaw.Refusal`:
  `:unknown_admission`, `:ceiling_unmet` (raised before the engine is called),
  `:projection_failed` (also for a subject without a resource), `:missing_law_module`,
  `:law_module_failed` (a law module that raises is converted, never propagated) or an engine code.

  ## Atomic behavior

  `atomic/3` returns `{:not_atomic, "GraphLaw admission requires a WASM call"}`. An admission needs
  an engine round trip, which cannot be compiled into a data-layer expression, so Ash falls back to
  the non-atomic path (for example `Ash.bulk_update/4` with `strategy: :stream`) and refuses
  `strategy: :atomic`.

  ## Telemetry

  `admit/2` emits `[:ash_graphlaw, :admission, :stop]` with measurements
  `%{duration: native_time}` and metadata
  `%{admission: atom, outcome: :admitted | :refused, code: atom | nil, standing: atom}`.

  ## Authority

  GraphLaw derives and validates; it never authorizes. A passing validation is an observation of
  one projected input, not a grant of authority, and its standing is at most `:PARTIAL_ALIVE`.
  """

  use Ash.Resource.Validation

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Authority
  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Projection
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Standing

  @default_lease_key :graphlaw_lease

  @typedoc "What an admission can be run against: a changeset, query or action input."
  @type subject :: Projection.subject()

  @typedoc """
  Validation options: `:admission` (required), `:projection`, `:server`, `:timeout` (ms) and
  `:lease_key` (default `:graphlaw_lease`).
  """
  @type opts :: [
          admission: atom(),
          projection: module() | nil,
          server: GenServer.server(),
          timeout: pos_integer(),
          lease_key: atom()
        ]

  @doc """
  Validates and normalizes the options.

  Returns `{:ok, opts}` with `:admission`, `:projection` and `:lease_key` populated, or
  `{:error, message}` when `:admission` is missing or not an atom, `:projection` is not a module,
  `:lease_key` is not an atom or `:timeout` is not a positive integer.
  """
  @impl Ash.Resource.Validation
  @spec init(keyword()) :: {:ok, opts()} | {:error, String.t()}
  def init(opts) do
    with {:ok, admission} <- fetch_atom(opts, :admission, true),
         {:ok, projection} <- fetch_module(opts, :projection),
         {:ok, lease_key} <- fetch_atom(opts, :lease_key, false),
         :ok <- check_timeout(opts[:timeout]) do
      {:ok,
       opts
       |> Keyword.put(:admission, admission)
       |> Keyword.put(:projection, projection)
       |> Keyword.put(:lease_key, lease_key || @default_lease_key)}
    end
  end

  @doc "Returns the subjects this validation supports: `Ash.Changeset` and `Ash.ActionInput`."
  @impl Ash.Resource.Validation
  @spec supports(opts()) :: [module()]
  def supports(_opts), do: [Ash.Changeset, Ash.ActionInput]

  @doc """
  Returns `:ok` when the engine admits the projected input, otherwise
  `{:error, %AshGraphLaw.Error.Refused{}}` carrying the typed refusal.
  """
  @impl Ash.Resource.Validation
  @spec validate(subject(), opts(), Ash.Resource.Validation.Context.t()) :: :ok | {:error, Exception.t()}
  def validate(subject, opts, _context) do
    case admit(subject, opts) do
      :ok -> :ok
      {:error, %Refusal{} = refusal} -> {:error, Refused.exception(refusal: refusal)}
    end
  end

  @doc """
  Declares the validation non-atomic: `{:not_atomic, "GraphLaw admission requires a WASM call"}`.
  """
  @impl Ash.Resource.Validation
  @spec atomic(subject(), opts(), Ash.Resource.Validation.Context.t()) :: {:not_atomic, String.t()}
  def atomic(_subject, _opts, _context), do: {:not_atomic, "GraphLaw admission requires a WASM call"}

  @doc "Describes the validation for error messages (`message` and `vars`)."
  @impl Ash.Resource.Validation
  @spec describe(opts()) :: [message: String.t(), vars: list()]
  def describe(opts) do
    [message: "must be admitted by GraphLaw admission #{inspect(opts[:admission])}", vars: []]
  end

  @doc """
  Runs the admission named in `opts` against `subject`.

  Flow: fetch the declared admission, check the authority ceiling (before the engine is called),
  project, compute the law steps, call GraphLaw. Returns `:ok` when the engine admitted the
  projected input, otherwise a typed `AshGraphLaw.Refusal`. Shared with
  `AshGraphLaw.Preparation.Admit`.
  """
  @spec admit(subject(), keyword()) :: :ok | {:error, Refusal.t()}
  def admit(subject, opts) do
    started = System.monotonic_time()
    result = run(subject, opts)
    emit(result, opts, System.monotonic_time() - started)

    case result do
      {:ok, _admitted} -> :ok
      {:error, %Refusal{}} = error -> error
    end
  end

  # -- flow -----------------------------------------------------------------

  defp run(subject, opts) do
    lease_key = Keyword.get(opts, :lease_key, @default_lease_key)
    lease = context_of(subject)[lease_key]

    with {:ok, resource} <- resource_of(subject),
         {:ok, admission} <- Admissions.fetch(resource, opts[:admission]),
         :ok <- Authority.check_ceiling(admission, lease),
         {:ok, data} <- project(subject, admission, opts),
         {:ok, steps} <- steps(subject, admission) do
      AshGraphLaw.law(
        %{"text" => data.text, "dialect" => data.dialect},
        steps,
        Authority.engine_opts(resource, lease, opts)
      )
    end
  end

  defp resource_of(%{resource: resource}) when is_atom(resource) and not is_nil(resource), do: {:ok, resource}

  defp resource_of(_subject),
    do: {:error, Refusal.new(:projection_failed, "subject has no resource to look up an admission on")}

  defp context_of(%{context: context}) when is_map(context), do: context
  defp context_of(_subject), do: %{}

  defp project(subject, admission, opts) do
    case law_data(subject, admission) do
      :default -> default_projection(subject, admission, opts)
      settled -> settled
    end
  end

  defp default_projection(subject, admission, opts) do
    module = opts[:projection] || admission.projection || Projection.Default

    subject
    |> then(fn subject -> safe(fn -> module.data(subject, []) end, :projection_failed) end)
    |> projected()
  end

  defp projected({:ok, %{text: text, dialect: dialect} = data}) when is_binary(text) and is_binary(dialect),
    do: {:ok, data}

  defp projected({:error, %Refusal{}} = error), do: error
  defp projected(other), do: {:error, Refusal.new(:projection_failed, "projection returned #{inspect(other)}")}

  defp law_data(subject, %{law: law} = admission) when is_atom(law) and not is_nil(law) do
    if Code.ensure_loaded?(law) and function_exported?(law, :data, 2),
      do: call_law_data(law, subject, admission),
      else: :default
  end

  defp law_data(_subject, _admission), do: :default

  defp call_law_data(law, subject, admission) do
    fn -> law.data(subject, admission) end
    |> safe(:law_module_failed)
    |> law_projected()
  end

  defp law_projected({:ok, %{text: _, dialect: _}} = ok), do: ok
  defp law_projected({:error, %Refusal{}} = error), do: error
  defp law_projected(_other), do: :default

  defp steps(subject, %{law: law} = admission) when is_atom(law) and not is_nil(law) do
    case safe(fn -> law.steps(subject, admission) end, :law_module_failed) do
      steps when is_list(steps) -> {:ok, steps}
      {:error, %Refusal{}} = error -> error
      other -> {:error, Refusal.new(:law_module_failed, "law steps/2 returned #{inspect(other)}")}
    end
  end

  defp steps(_subject, %{step: step}) when step in [:rdfs, :owl_rl] do
    {:ok, [%{"step" => step |> Atom.to_string() |> String.replace("_", "-")}]}
  end

  defp steps(_subject, %{step: step, name: name}) do
    {:error,
     Refusal.new(:missing_law_module, "admission #{inspect(name)} (step #{inspect(step)}) requires a law module", %{
       admission: name
     })}
  end

  # Runs a user-supplied callback; converts crashes into typed refusals instead of raising.
  defp safe(fun, code) do
    fun.()
  rescue
    exception -> {:error, Refusal.new(code, Exception.message(exception), %{exception: inspect(exception.__struct__)})}
  end

  defp emit(result, opts, duration) do
    {outcome, code} =
      case result do
        {:ok, _} -> {:admitted, nil}
        {:error, %Refusal{code: code}} -> {:refused, code}
      end

    :telemetry.execute([:ash_graphlaw, :admission, :stop], %{duration: duration}, %{
      admission: opts[:admission],
      outcome: outcome,
      code: code,
      standing: Standing.of(result)
    })
  end

  # -- option validation ------------------------------------------------------

  defp fetch_atom(opts, key, required?) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_atom(value) and not is_nil(value) -> {:ok, value}
      :error when not required? -> {:ok, nil}
      {:ok, nil} when not required? -> {:ok, nil}
      _ -> {:error, "#{inspect(key)} must be an atom#{if required?, do: " (required)", else: ""}"}
    end
  end

  defp fetch_module(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:ok, nil}
      module when is_atom(module) -> {:ok, module}
      _ -> {:error, "#{inspect(key)} must be a module or nil"}
    end
  end

  defp check_timeout(nil), do: :ok
  defp check_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp check_timeout(_), do: {:error, ":timeout must be a positive integer"}
end
