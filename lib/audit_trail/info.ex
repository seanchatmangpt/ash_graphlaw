



defmodule AuditTrail.Resource.Info do
  @moduledoc """
  Public introspection API for `audit_trail`.
  """

  @doc "Returns the raw `:audit` DSL entities declared on `resource`."
  def audit(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:audit])
  end

  @doc "Returns the transformer-normalized compiled state for `resource`, or `nil` if the extension is not present."
  def compiled(resource) do
    case compiled_result(resource) do
      {:ok, compiled} -> compiled
      {:error, _} -> nil
    end
  end

  @doc """
  Returns `{:ok, compiled}` or `{:error, :not_compiled}` for `resource`.

  """
  def compiled_result(resource) do
    case Spark.Dsl.Extension.get_persisted(resource, :audit_trail_compiled, nil) do
      nil -> {:error, :not_compiled}
      compiled -> {:ok, compiled}
    end

  end

  @doc "Bang variant of `compiled_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def compiled!(resource) do
    case compiled_result(resource) do
      {:ok, compiled} -> compiled
      {:error, reason} -> raise ArgumentError, "AuditTrail.Resource.Info.compiled!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry compiled `audit_trail` state?"
  def compiled?(resource) do
    match?({:ok, _}, compiled_result(resource))
  end

end
