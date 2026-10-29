



defmodule AshR2RML.Resource.Persist do
  @moduledoc """
  Transformer for `ash_r2rml`: normalizes the raw `:r2rml, :sparql`
  DSL entities into a compiled struct and persists it as `:ash_r2rml_compiled`.
  """
  use Spark.Dsl.Transformer


  @impl true
  def transform(dsl_state) do


    r2rml_entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:r2rml])

    sparql_entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:sparql])


    compiled = %{
      r2rml: r2rml_entities,
      sparql: sparql_entities,
    }


    {:ok, Spark.Dsl.Transformer.persist(dsl_state, :ash_r2rml_compiled, compiled)}
  end

end
