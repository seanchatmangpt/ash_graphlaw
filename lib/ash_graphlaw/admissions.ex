# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Admissions do
  @moduledoc """
  UNSUPPORTED(generator-capability): read side of the `:graphlaw` DSL section.

  Reads entities with `Spark.Dsl.Extension.get_entities/2` directly and never calls the generated Info
  module. A module lacking the extension yields a typed `AshGraphLaw.Refusal` (`:unknown_admission`).
  """

  alias AshGraphLaw.Dsl.{Admission, Runtime}
  alias AshGraphLaw.Refusal

  @doc "Returns every admission declared on `resource` (empty when the module lacks the extension)."
  @spec all(module()) :: [struct()]
  def all(resource) do
    case entities(resource) do
      {:ok, entities} -> Enum.filter(entities, &is_struct(&1, Admission))
      {:error, _refusal} -> []
    end
  end

  @doc "Fetches the admission named `name`, or a typed `:unknown_admission` refusal."
  @spec fetch(module(), atom()) :: {:ok, struct()} | {:error, Refusal.t()}
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

  @doc "Returns the runtime settings of `resource`, or struct defaults when the section omits them."
  @spec runtime(module()) :: struct()
  def runtime(resource) do
    case entities(resource) do
      {:ok, entities} -> Enum.find(entities, &is_struct(&1, Runtime)) || struct(Runtime)
      {:error, _refusal} -> struct(Runtime)
    end
  end

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
