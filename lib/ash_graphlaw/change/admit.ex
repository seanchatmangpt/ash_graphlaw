# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Change.Admit do
  @moduledoc """
  Ash change that runs a declared GraphLaw admission against a changeset.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits an Ash change.

      create :open do
        change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
      end

  ## Options

    * `:admission` (required) - name of an `admission` declared in the resource's `graphlaw` section.
    * `:projection` - module implementing `AshGraphLaw.Projection`; defaults to the admission's
      `projection`, then `AshGraphLaw.Projection.Default`.
    * `:server` - pool/host server name (default `AshGraphLaw.Pool`).
    * `:timeout` - per-call timeout in ms (default: the runtime section's `timeout_ms`).
    * `:phase` - `:before_action` (default) or `:before_transaction`.
    * `:lease_key` - changeset context key holding the lease (default `:graphlaw_lease`).

  ## Flow

    1. `AshGraphLaw.Admissions.fetch/2` resolves the declared admission.
    2. The admission `ceiling` is compared with the signed lease found at
       `changeset.context[lease_key]` (order `:observe < :select < :construct`) by
       `AshGraphLaw.Authority.check_ceiling/2`. An unmet ceiling refuses with
       `:ceiling_unmet` BEFORE the engine is called. `:observe` needs no lease. A bare
       ceiling atom or an unsigned map grants only `:observe`.
    3. The projection produces N-Triples (or the law module's own `data/2`).
    4. `input_digest` is the sha256 of the projected text.
    5. `Law.steps/2` supplies the GraphLaw `law` steps; `AshGraphLaw.law/3` runs them.
    6. On success an `AshGraphLaw.Evidence` is stored at `changeset.context.graphlaw`;
       on refusal an `AshGraphLaw.Error.Refused` is added to the changeset.

  ## Lease

  The lease is a map or keyword list with a `:signed_lease` entry (`%{"lease" => ..., "attestation"
  => ...}`). Only that entry can raise the ceiling above `:observe`, and the engine verifies its
  signature and expiry against the resource's `runtime.trusted_keys` on the same request. Trust
  anchors, skew and the clock are never taken from changeset context. See `AshGraphLaw.Authority`.

  ## Authority

  Evidence is an observation bound to an exact input digest, the engine's `wasm_sha256` and the
  identity of the signed lease that was presented. It is never authority: nothing here grants,
  extends or renews a lease. Standing is derived with `AshGraphLaw.Standing.of/1`
  (an admitted result is `:PARTIAL_ALIVE`, never `:ALIVE`).

  ## Telemetry

  `[:ash_graphlaw, :admission, :stop]` with measurements `%{duration: native_time}` and
  metadata `%{admission, outcome, code, standing}`.
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

  @allowed_keys [:admission, :projection, :server, :timeout, :phase, :lease_key]
  @phases [:before_action, :before_transaction]
  @action_types [:create, :update, :destroy]

  @impl true
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

  @impl true
  def change(%Changeset{action_type: type} = changeset, opts, _context) when type in @action_types do
    case Keyword.get(opts, :phase, :before_action) do
      :before_action -> Changeset.before_action(changeset, &run(&1, opts))
      :before_transaction -> Changeset.before_transaction(changeset, &run(&1, opts))
    end
  end

  def change(changeset, _opts, _context), do: changeset

  @impl true
  def atomic(_changeset, _opts, _context), do: {:not_atomic, "GraphLaw admission requires a WASM call"}

  @doc false
  @spec run(Changeset.t(), keyword()) :: Changeset.t()
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
