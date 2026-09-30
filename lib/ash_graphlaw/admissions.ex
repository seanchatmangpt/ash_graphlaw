# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits DSL legality/authority semantics

defmodule AshGraphLaw.Admissions do
  @moduledoc """
  UNSUPPORTED(generator-capability): read side of the `:graphlaw` DSL section.

  Reads entities with `Spark.Dsl.Extension.get_entities/2` directly and never calls the generated Info
  module. A module lacking the extension yields a typed `AshGraphLaw.Refusal` (`:unknown_admission`).
  """

  alias AshGraphLaw.Dsl.{Admission, Runtime}
  alias AshGraphLaw.Refusal

  @typedoc "A `%AshGraphLaw.Dsl.Admission{}` entity declared in the `:graphlaw` section."
  @type admission :: %Admission{}

  @typedoc "The `%AshGraphLaw.Dsl.Runtime{}` entity (or its defaults) of a resource."
  @type runtime :: %Runtime{}

  @doc """
  Returns every admission declared on `resource` (empty when the module lacks the extension).

  Never raises and never returns a refusal: use `fetch/2` when the distinction between
  "no admissions" and "not an AshGraphLaw resource" matters.
  """
  @spec all(module()) :: [admission()]
  def all(resource) do
    case entities(resource) do
      {:ok, entities} -> Enum.filter(entities, &is_struct(&1, Admission))
      {:error, _refusal} -> []
    end
  end

  @doc """
  Fetches the admission named `name`, or a typed `:unknown_admission` refusal.

  The refusal details list the `:known` admission names when the resource uses the extension,
  and carry the underlying error message when it does not.
  """
  @spec fetch(module(), atom()) :: {:ok, admission()} | {:error, Refusal.t()}
  def fetch(resource, name) do
    with {:ok, entities} <- entities(resource) do
      case Enum.find(entities, &(is_struct(&1, Admission) and &1.name == name)) do
        nil ->
          {:error,
           Refusal.new(:unknown_admission, "no admission #{inspect(name)} on #{inspect(resource)}", %{
             resource: inspect(resource),
             admission: name,
             known: entities |> Enum.filter(&is_struct(&1, Admission)) |> Enum.map(& &1.name)
           })}

        admission ->
          {:ok, admission}
      end
    end
  end

  @doc """
  Returns the runtime settings of `resource`, or struct defaults when the section omits them.

  The runtime is the only source of `trusted_keys`, `max_skew_secs` and `timeout_ms`; see
  `AshGraphLaw.Authority.engine_opts/3`.
  """
  @spec runtime(module()) :: runtime()
  def runtime(resource) do
    case entities(resource) do
      {:ok, entities} -> Enum.find(entities, &is_struct(&1, Runtime)) || struct(Runtime)
      {:error, _refusal} -> struct(Runtime)
    end
  end

  @doc """
  Returns every `capability` declared on `resource`, in declaration order (empty when the
  module lacks the extension or declares none).

  Reads `Spark.Dsl.Extension.get_entities/2` directly; never the generated Info module.
  """
  @spec capabilities(module()) :: [struct()]
  def capabilities(resource) do
    case entities(resource) do
      {:ok, entities} -> Enum.filter(entities, &capability?/1)
      {:error, _refusal} -> []
    end
  end

  @doc """
  Fetches the capability named `name` (atom or string), or a typed `:capability_not_declared`
  refusal listing the `:known` declared names.
  """
  @spec capability(module(), atom() | String.t()) :: {:ok, struct()} | {:error, Refusal.t()}
  def capability(resource, name) do
    declared = capabilities(resource)

    case Enum.find(declared, &(to_string(&1.name) == to_string(name))) do
      nil ->
        {:error,
         Refusal.new(:capability_not_declared, "capability #{inspect(name)} is not declared on #{inspect(resource)}", %{
           resource: inspect(resource),
           capability: to_string(name),
           known: Enum.map(declared, &to_string(&1.name))
         })}

      capability ->
        {:ok, capability}
    end
  end

  @doc """
  True when `resource` declares a capability named `name` (atom or string).
  """
  @spec declared?(module(), atom() | String.t()) :: boolean()
  def declared?(resource, name), do: match?({:ok, _}, capability(resource, name))

  # Matched by struct name so this module carries no compile-time dependency on the generated
  # `AshGraphLaw.Dsl.Capability` struct.
  defp capability?(%{__struct__: AshGraphLaw.Dsl.Capability}), do: true
  defp capability?(_other), do: false

  @spec entities(module()) :: {:ok, [struct()]} | {:error, Refusal.t()}
  defp entities(resource) do
    {:ok, Spark.Dsl.Extension.get_entities(resource, [:graphlaw])}
  rescue
    error ->
      {:error,
       Refusal.new(:unknown_admission, "#{inspect(resource)} does not use the AshGraphLaw.Resource extension", %{
         resource: inspect(resource),
         error: Exception.message(error)
       })}
  end
end
