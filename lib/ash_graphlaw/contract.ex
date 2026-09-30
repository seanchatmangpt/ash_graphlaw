# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits DSL legality/authority semantics

defmodule AshGraphLaw.Contract do
  @moduledoc """
  UNSUPPORTED(generator-capability): hand-written legality contract for the `:graphlaw` DSL section.

  GraphLaw derives and validates; it never authorizes. This module only checks the declared shape.

  Delegate of the generated `AshGraphLaw.Resource.Verify` (ash-extension-pack `verify.ex.tmpl`).

  ## Findings from the vendored pack templates (read-only, `ash-extension-pack/templates`)

    * `persist.ex.tmpl` builds `compiled = %{<section>: entities, ...}` with one key per
      `aex:DslSection` (here only `:graphlaw`) holding the raw entity list from
      `Spark.Dsl.Transformer.get_entities(dsl_state, [:graphlaw])`, plus `metadata: %{source: _}`
      only when `aex:provenanceSource` is set. It persists that map under `:ash_graphlaw_compiled`.
      So `compiled.graphlaw` is a list mixing `%AshGraphLaw.Dsl.Runtime{}` and
      `%AshGraphLaw.Dsl.Admission{}` structs.
    * `verify.ex.tmpl` first checks that `:ash_graphlaw_compiled` was persisted, then (with a delegate
      configured) calls `Contract.validate(compiled)`. `:ok` passes; `{:error, refusals}` is wrapped in a
      single `Spark.Error.DslError` whose message is `Enum.map_join(refusals, "; ", &"\#{&1.code}: \#{&1.detail}")`.
      Every refusal therefore must be a map with `:code` and `:detail`.
    * `info.ex.tmpl` reads the same persisted key; hand-written code does not use it and reads entities via
      `AshGraphLaw.Admissions` instead.

  Refusal codes emitted here belong to the closed `AshGraphLaw.Refusal` table:
  `:duplicate_admission`, `:missing_law_module`, `:invalid_trusted_key`, `:invalid_runtime_option`,
  plus, for `capability` entities, `:duplicate_capability`, `:unknown_capability` and `:ceiling_unmet`
  (these are verifier finding labels rendered into a `Spark.Error.DslError` message).
  """

  @payload_steps [:shacl, :n3, :hooks, :plan, :require_receipt, :require_signed_receipt]
  @hex_key ~r/\A[0-9a-fA-F]{64}\z/

  @type refusal :: %{code: atom(), detail: String.t()}

  @doc "Steps that need a payload supplied by a law module."
  @spec payload_steps() :: [atom()]
  def payload_steps, do: @payload_steps

  @doc """
  Validates the persisted compiled state.

  Returns `:ok` or `{:error, [%{code: atom, detail: String.t()}]}`. Fail-closed: a `compiled`
  value that is not a map with a `:graphlaw` entity list (the shape `Persist` produces) is an
  error, never `:ok` with zero entities.
  """
  @spec validate(term()) :: :ok | {:error, [refusal()]}
  def validate(%{graphlaw: list} = compiled) when is_list(list), do: validate_entities(compiled)

  def validate(other) do
    {:error,
     [
       refusal(
         :invalid_runtime_option,
         "compiled state is malformed: expected a map with a :graphlaw entity list, got #{inspect(other, limit: 5)}"
       )
     ]}
  end

  defp validate_entities(compiled) do
    entities = entities(compiled)
    admissions = Enum.filter(entities, &is_struct(&1, AshGraphLaw.Dsl.Admission))
    runtimes = Enum.filter(entities, &is_struct(&1, AshGraphLaw.Dsl.Runtime))
    capabilities = Enum.filter(entities, &match?(%{__struct__: AshGraphLaw.Dsl.Capability}, &1))

    refusals =
      duplicate_refusals(admissions) ++
        law_refusals(admissions) ++
        Enum.flat_map(runtimes, &runtime_refusals/1) ++
        capability_refusals(capabilities)

    case refusals do
      [] -> :ok
      _ -> {:error, refusals}
    end
  end

  defp entities(%{graphlaw: list}), do: list

  defp duplicate_refusals(admissions) do
    admissions
    |> Enum.frequencies_by(& &1.name)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {name, count} ->
      refusal(:duplicate_admission, "admission #{inspect(name)} is declared #{count} times")
    end)
  end

  defp law_refusals(admissions) do
    missing =
      for %{step: step, law: nil, name: name} <- admissions, step in @payload_steps do
        refusal(
          :missing_law_module,
          "admission #{inspect(name)} uses step #{inspect(step)} and requires a `law` module"
        )
      end

    broken =
      for %{law: law, name: name} <- admissions, is_atom(law) and not is_nil(law), defect = law_defect(law) do
        refusal(:missing_law_module, "admission #{inspect(name)}: law module #{inspect(law)} #{defect}")
      end

    missing ++ broken
  end

  # A declared law module must exist and export steps/2, judged at compile time. A module that
  # is still compiling (`:unavailable`, e.g. a law that refers back to its resource) cannot be
  # judged here; Change.Admit and Validation.Admissible turn a bad law into a typed
  # `:law_module_failed` refusal at run time.
  defp law_defect(law) do
    case Code.ensure_compiled(law) do
      {:module, ^law} -> if function_exported?(law, :steps, 2), do: nil, else: "does not export steps/2"
      {:error, :unavailable} -> nil
      {:error, reason} -> "is not available (#{reason})"
    end
  end

  # Capability checks: name in the GraphLaw registry, ceiling >= the op's minimum, no duplicates.
  # Matched by struct name so this module needs no compile-time dependency on the generated struct.
  defp capability_refusals([]), do: []

  defp capability_refusals(capabilities) do
    duplicates =
      capabilities
      |> Enum.frequencies_by(&to_string(&1.name))
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.sort()
      |> Enum.map(fn {name, count} ->
        refusal(:duplicate_capability, "capability #{inspect(name)} is declared #{count} times")
      end)

    duplicates ++
      case registry_names() do
        {:ok, names} -> Enum.flat_map(capabilities, &capability_refusal(&1, names))
        {:error, detail} -> [refusal(:unknown_capability, detail)]
      end
  end

  defp capability_refusal(%{name: name, ceiling: ceiling}, names) do
    name = to_string(name)

    if name in names do
      ceiling_refusal(name, ceiling)
    else
      [
        refusal(
          :unknown_capability,
          "capability #{inspect(name)} is not in the GraphLaw registry (known: #{Enum.join(names, ", ")})"
        )
      ]
    end
  end

  defp ceiling_refusal(name, ceiling) do
    case AshGraphLaw.Authority.op_ceiling(name) do
      {:ok, required} ->
        if rank(ceiling) >= rank(required) do
          []
        else
          [
            refusal(
              :ceiling_unmet,
              "capability #{inspect(name)} declares ceiling #{inspect(ceiling)}, below the required #{inspect(required)}"
            )
          ]
        end

      {:error, %{message: message}} ->
        [refusal(:unknown_capability, message)]
    end
  end

  defp rank(:observe), do: 0
  defp rank(:select), do: 1
  defp rank(:construct), do: 2
  defp rank(_other), do: -1

  defp registry_names do
    registry = AshGraphLaw.Capability.Registry

    case Code.ensure_compiled(registry) do
      {:module, ^registry} ->
        if function_exported?(registry, :names, 0),
          do: {:ok, apply(registry, :names, [])},
          else: {:error, "capability registry #{inspect(registry)} does not export names/0"}

      {:error, reason} ->
        {:error,
         "cannot validate capability declarations: #{inspect(registry)} is not available (#{reason}); run scripts/ggen_sync.sh"}
    end
  end

  defp runtime_refusals(runtime) do
    timeout = timeout_refusals(runtime.timeout_ms)
    skew = skew_refusals(runtime.max_skew_secs)
    keys = key_refusals(runtime.trusted_keys)
    timeout ++ skew ++ keys
  end

  defp timeout_refusals(value) when is_integer(value) and value > 0, do: []

  defp timeout_refusals(value),
    do: [refusal(:invalid_runtime_option, "timeout_ms must be a positive integer, got #{inspect(value)}")]

  defp skew_refusals(value) when is_integer(value) and value >= 0, do: []

  defp skew_refusals(value),
    do: [refusal(:invalid_runtime_option, "max_skew_secs must be a non-negative integer, got #{inspect(value)}")]

  defp key_refusals(keys) when is_list(keys) do
    for key <- keys, not valid_key?(key) do
      refusal(:invalid_trusted_key, "trusted key #{inspect(key)} is not a 64-character hex string")
    end
  end

  defp key_refusals(other),
    do: [refusal(:invalid_trusted_key, "trusted_keys must be a list of hex strings, got #{inspect(other)}")]

  defp valid_key?(key), do: is_binary(key) and Regex.match?(@hex_key, key)

  defp refusal(code, detail), do: %{code: code, detail: detail}
end
