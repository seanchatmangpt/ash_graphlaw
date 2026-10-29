



defmodule AshR2RML.Resource.Info do
  @moduledoc """
  Public introspection API for `ash_r2rml`.
  """

  @doc "Returns the raw `:r2rml` DSL entities declared on `resource`."
  def r2rml(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:r2rml])
  end

  @doc "Returns the raw `:sparql` DSL entities declared on `resource`."
  def sparql(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:sparql])
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
    case Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_compiled, nil) do
      nil -> {:error, :not_compiled}
      compiled -> {:ok, compiled}
    end

  end

  @doc "Bang variant of `compiled_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def compiled!(resource) do
    case compiled_result(resource) do
      {:ok, compiled} -> compiled
      {:error, reason} -> raise ArgumentError, "AshR2RML.Resource.Info.compiled!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry compiled `ash_r2rml` state?"
  def compiled?(resource) do
    match?({:ok, _}, compiled_result(resource))
  end

end
