defmodule AshGraphLaw.Resource.Persist do
  @moduledoc """
  Transformer for `ash_graphlaw`: normalizes the raw `:graphlaw`
  DSL entities into a compiled struct and persists it as `:ash_graphlaw_compiled`.
  """
  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    graphlaw_entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:graphlaw])

    compiled = %{
      graphlaw: graphlaw_entities
    }

    {:ok, Spark.Dsl.Transformer.persist(dsl_state, :ash_graphlaw_compiled, compiled)}
  end
end
