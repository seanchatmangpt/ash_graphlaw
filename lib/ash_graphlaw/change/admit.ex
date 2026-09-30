# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Change.Admit do
  @moduledoc """
  Ash change that runs a declared GraphLaw admission against a changeset.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits an Ash change.

  ## Usage

      create :open do
        change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
      end

      update :close do
        change {AshGraphLaw.Change.Admit, admission: :ticket_close, phase: :before_transaction}
      end

  The change applies to `:create`, `:update` and `:destroy` actions. On any other action type
  (for example `:read`) it returns the changeset untouched.

  ## Options

  See `t:opts/0`.

  | Option        | Type            | Default                                    | Meaning |
  |---------------|-----------------|--------------------------------------------|---------|
  | `:admission`  | atom (required) | none                                       | Name of an `admission` declared in the resource's `graphlaw` section. |
  | `:projection` | module or `nil` | the admission's `projection`, then `AshGraphLaw.Projection.Default` | Module implementing `AshGraphLaw.Projection`. |
  | `:server`     | atom            | `AshGraphLaw.Pool`                         | Pool/host server name the engine call is sent to. |
  | `:timeout`    | positive integer (ms) | the runtime section's `timeout_ms`   | Per-call timeout. |
  | `:phase`      | `:before_action` or `:before_transaction` | `:before_action`   | Changeset hook the admission runs in. |
  | `:lease_key`  | atom            | `:graphlaw_lease`                          | Changeset context key holding the lease. |

  Unknown keys, a missing or non-atom `:admission`, an unknown `:phase`, a non-atom
  `:projection`, a non-positive `:timeout` and a non-atom `:lease_key` are rejected by `init/1`
  when the resource is compiled.

  ## Lease context key

  The lease is read from `changeset.context[lease_key]` (default `:graphlaw_lease`). Supply it
  when building the changeset:

      Ash.Changeset.for_create(Ticket, :open, params, context: %{graphlaw_lease: lease})

  The lease is a map or keyword list with a `:signed_lease` entry
  (`%{"lease" => ..., "attestation" => ...}`). Only that entry can raise the ceiling above
  `:observe`, and the engine verifies its signature and expiry against the resource's
  `runtime.trusted_keys` on the same request. Trust anchors, skew and the clock are never taken
  from changeset context. A bare ceiling atom or an unsigned map grants only `:observe`. See
  `AshGraphLaw.Authority`.

  ## Flow

    1. `AshGraphLaw.Admissions.fetch/2` resolves the declared admission.
    2. The admission `ceiling` is compared with the signed lease (order
       `:observe < :select < :construct`) by `AshGraphLaw.Authority.check_ceiling/2`. An unmet
       ceiling refuses with `:ceiling_unmet` BEFORE the engine is called. `:observe` needs no
       lease.
    3. The projection produces N-Triples (or the law module's own `data/2`, when the admission's
       `law` module exports it).
    4. `input_digest` is the sha256 of the projected text.
    5. `law.steps/2` supplies the GraphLaw `law` steps; an admission without a law module maps
       `:rdfs` and `:owl_rl` to the built-in step and refuses any other step with
       `:missing_law_module`. `AshGraphLaw.law/3` runs the steps.
    6. On success an `AshGraphLaw.Evidence` is stored at `changeset.context.graphlaw`; on refusal
       an `AshGraphLaw.Error.Refused` is added to the changeset.

  ## Refusals

  Every failure is an `AshGraphLaw.Refusal` wrapped in `AshGraphLaw.Error.Refused` and added to
  the changeset, never raised out of the action:

    * `:unknown_admission` - the resource declares no admission with that name.
    * `:ceiling_unmet` - the presented lease does not reach the admission's ceiling.
    * `:projection_failed` - the projection returned an unexpected value.
    * `:missing_law_module` - the step is neither `:rdfs` nor `:owl_rl` and no law module exists.
    * `:law_module_failed` - the law module's `steps/2` raised or returned a non-list.
    * Any engine-side code produced by `AshGraphLaw.law/3`.

  The code table is closed; see `AshGraphLaw.Refusal.codes/0`.

  ## Atomic behavior

  `atomic/3` always returns `{:not_atomic, "GraphLaw admission requires a WASM call"}`. The
  admission needs an engine round trip per record, which cannot be expressed as a data-layer
  expression, so Ash cannot compile this change into an atomic update:

    * `Ash.bulk_update/4` with `strategy: :atomic` is refused by Ash and surfaces this reason;
      nothing is changed.
    * `strategy: :stream` runs the change per record through `change/3`; every record is
      admitted independently and a refusal leaves that record unchanged.
    * There is no batch callback; there is one admission call per record.

  This behavior is exercised by `test/ash/atomic_test.exs`.

  ## Authority

  Evidence is an observation bound to an exact input digest, the engine's `wasm_sha256` and the
  identity of the signed lease that was presented. It is never authority: nothing here grants,
  extends or renews a lease. Standing is derived with `AshGraphLaw.Standing.of/1` (an admitted
  result is `:PARTIAL_ALIVE`, never `:ALIVE`).

  ## Telemetry

  `[:ash_graphlaw, :admission, :stop]` with measurements `%{duration: native_time}` and metadata
  `%{admission: atom, outcome: :admitted | :refused, code: atom | nil, standing: atom}`. It is
  emitted once per admission attempt, after the outcome is known.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Authority
  alias AshGraphLaw.Dsl.Admission
  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Evidence
  alias AshGraphLaw.Projection.Default, as: DefaultProjection
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Standing

  @typedoc """
  Options accepted by `init/1`.

    * `:admission` - declared admission name (required).
    * `:projection` - `AshGraphLaw.Projection` module override.
    * `:server` - pool/host server name.
    * `:timeout` - per-call timeout in ms (positive integer).
    * `:phase` - `:before_action` (default) or `:before_transaction`.
    * `:lease_key` - changeset context key holding the lease (default `:graphlaw_lease`).
  """
  @type opts :: [
          admission: atom(),
          projection: module() | nil,
          server: GenServer.server(),
          timeout: pos_integer(),
          phase: phase(),
          lease_key: atom()
        ]

  @typedoc "Changeset hook the admission runs in."
  @type phase :: :before_action | :before_transaction

  @allowed_keys [:admission, :projection, :server, :timeout, :phase, :lease_key]
  @phases [:before_action, :before_transaction]
  @action_types [:create, :update, :destroy]

  @doc """
  Validates the change options at resource compile time.

  Returns `{:ok, opts}` or `{:error, message}` for unknown keys, a missing `:admission`, an
  invalid `:phase`, a non-atom `:projection`, a non-positive `:timeout` or a non-atom `:lease_key`.
  """
  @impl true
  @spec init(term()) :: {:ok, opts()} | {:error, String.t()}
  def init(opts) when is_list(opts) do
    with :ok <- check_keys(opts),
         :ok <- check_admission(opts[:admission]),
         :ok <- check_phase(Keyword.get(opts, :phase, :before_action)),
         :ok <- check_module(:projection, opts[:projection]),
         :ok <- check_timeout(opts[:timeout]),
         :ok <- check_lease_key(Keyword.get(opts, :lease_key, :graphlaw_lease)) do
      {:ok, opts}
    end
  end

  def init(_opts), do: {:error, "AshGraphLaw.Change.Admit options must be a keyword list"}

  @doc """
  Registers the admission on `changeset` in the configured `:phase`.

  Applies to `:create`, `:update` and `:destroy`; other action types return the changeset
  unchanged. The admission itself runs later, in the registered hook.
  """
  @impl true
  @spec change(Changeset.t(), opts(), Ash.Resource.Change.context()) :: Changeset.t()
  def change(%Changeset{action_type: type} = changeset, opts, _context) when type in @action_types do
    case Keyword.get(opts, :phase, :before_action) do
      :before_action -> Changeset.before_action(changeset, &run(&1, opts))
      :before_transaction -> Changeset.before_transaction(changeset, &run(&1, opts))
    end
  end

  def change(changeset, _opts, _context), do: changeset

  @doc """
  Declares the change non-atomic: `{:not_atomic, "GraphLaw admission requires a WASM call"}`.

  Never needs the engine. See the "Atomic behavior" section of the module documentation.
  """
  @impl true
  @spec atomic(Changeset.t(), opts(), Ash.Resource.Change.context()) :: {:not_atomic, String.t()}
  def atomic(_changeset, _opts, _context), do: {:not_atomic, "GraphLaw admission requires a WASM call"}

  @doc """
  Runs the admission named in `opts` against `changeset` and folds the outcome into it.

  This is the hook body registered by `change/3`; it is public only so the hook can be captured.
  On success the `AshGraphLaw.Evidence` is stored at `changeset.context.graphlaw`; on refusal an
  `AshGraphLaw.Error.Refused` is added to the changeset. Emits the
  `[:ash_graphlaw, :admission, :stop]` telemetry event either way.
  """
  @spec run(Changeset.t(), opts()) :: Changeset.t()
  def run(%Changeset{} = changeset, opts) do
    started = System.monotonic_time()
    name = Keyword.fetch!(opts, :admission)
    result = admit(changeset, name, opts)
    emit(name, result, System.monotonic_time() - started)

    case result do
      {:ok, evidence} -> Changeset.set_context(changeset, %{graphlaw: evidence})
      {:error, %Refusal{} = refusal} -> Changeset.add_error(changeset, Refused.exception(refusal: refusal))
    end
  end

  defp admit(changeset, name, opts) do
    resource = changeset.resource
    lease = Map.get(changeset.context, Keyword.get(opts, :lease_key, :graphlaw_lease))

    with {:ok, admission} <- Admissions.fetch(resource, name),
         :ok <- Authority.check_ceiling(admission, lease),
         {:ok, data} <- fetch_data(changeset, admission, opts),
         digest = sha256(data.text),
         {:ok, steps} <- law_steps(changeset, admission),
         engine_opts = Authority.engine_opts(resource, lease, opts),
         {:ok, admitted} <- AshGraphLaw.law(data, steps, engine_opts) do
      {:ok,
       Evidence.new(name, admitted, digest,
         wasm_sha256: AshGraphLaw.engine_sha256(engine_opts),
         lease: Authority.identity(lease)
       )}
    end
  end

  # A law module that is absent or raises is a typed refusal, never a crash in the action.
  defp law_steps(_changeset, %Admission{law: nil, step: step}) when step in [:rdfs, :owl_rl],
    do: {:ok, [%{"step" => step |> Atom.to_string() |> String.replace("_", "-")}]}

  defp law_steps(_changeset, %Admission{law: nil, name: name, step: step}) do
    {:error,
     Refusal.new(:missing_law_module, "admission #{inspect(name)} (step #{inspect(step)}) requires a law module", %{
       admission: name
     })}
  end

  defp law_steps(changeset, %Admission{law: law} = admission) do
    case law.steps(changeset, admission) do
      steps when is_list(steps) -> {:ok, steps}
      other -> {:error, Refusal.new(:law_module_failed, "law steps/2 returned #{inspect(other)}")}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(:law_module_failed, Exception.message(exception), %{exception: inspect(exception.__struct__)})}
  end

  defp fetch_data(changeset, %Admission{} = admission, opts) do
    case law_data(changeset, admission) do
      {:ok, data} -> {:ok, data}
      :default -> projection_data(changeset, admission, opts)
    end
  end

  defp law_data(changeset, %Admission{law: law} = admission) when is_atom(law) and not is_nil(law) do
    if Code.ensure_loaded?(law) and function_exported?(law, :data, 2),
      do: law.data(changeset, admission),
      else: :default
  end

  defp law_data(_changeset, _admission), do: :default

  defp projection_data(changeset, admission, opts) do
    projection = opts[:projection] || admission.projection || DefaultProjection

    case projection.data(changeset, admission: admission) do
      {:ok, %{text: text, dialect: dialect} = data} when is_binary(text) and is_binary(dialect) ->
        {:ok, data}

      {:error, %Refusal{} = refusal} ->
        {:error, refusal}

      other ->
        {:error,
         Refusal.new(:projection_failed, "projection returned an unexpected value", %{returned: inspect(other)})}
    end
  end

  defp sha256(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  defp emit(name, result, duration) do
    {outcome, code} =
      case result do
        {:ok, _evidence} -> {:admitted, nil}
        {:error, %Refusal{code: code}} -> {:refused, code}
      end

    standing =
      case result do
        {:ok, %Evidence{standing: standing}} -> standing
        {:error, refusal} -> Standing.of({:error, refusal})
      end

    :telemetry.execute([:ash_graphlaw, :admission, :stop], %{duration: duration}, %{
      admission: name,
      outcome: outcome,
      code: code,
      standing: standing
    })
  end

  defp check_keys(opts) do
    case Keyword.keys(opts) -- @allowed_keys do
      [] -> :ok
      unknown -> {:error, "unknown AshGraphLaw.Change.Admit options: #{inspect(unknown)}"}
    end
  end

  defp check_admission(name) when is_atom(name) and not is_nil(name), do: :ok
  defp check_admission(_name), do: {:error, "AshGraphLaw.Change.Admit requires an :admission atom"}

  defp check_phase(phase) when phase in @phases, do: :ok
  defp check_phase(phase), do: {:error, ":phase must be one of #{inspect(@phases)}, got: #{inspect(phase)}"}

  defp check_module(_key, nil), do: :ok
  defp check_module(_key, module) when is_atom(module), do: :ok
  defp check_module(key, other), do: {:error, "#{inspect(key)} must be a module, got: #{inspect(other)}"}

  defp check_timeout(nil), do: :ok
  defp check_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp check_timeout(other), do: {:error, ":timeout must be a positive integer, got: #{inspect(other)}"}

  defp check_lease_key(key) when is_atom(key), do: :ok
  defp check_lease_key(other), do: {:error, ":lease_key must be an atom, got: #{inspect(other)}"}
end
