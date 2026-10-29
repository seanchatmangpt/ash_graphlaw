



defmodule AuditTrail.Resource.Persist do
  @moduledoc """
  Transformer for `audit_trail`: normalizes the raw `:audit`
  DSL entities into a compiled struct and persists it as `:audit_trail_compiled`.
  """
  use Spark.Dsl.Transformer


  @impl true
  def transform(dsl_state) do


    audit_entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:audit])


    compiled = %{
      audit: audit_entities,
    }


    {:ok, Spark.Dsl.Transformer.persist(dsl_state, :audit_trail_compiled, compiled)}
  end

end
