



defmodule NotificationExtension.Resource.Persist do
  @moduledoc """
  Transformer for `notification_extension`: normalizes the raw `:notification`
  DSL entities into a compiled struct and persists it as `:notification_extension_compiled`.
  """
  use Spark.Dsl.Transformer


  @impl true
  def transform(dsl_state) do


    notification_entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:notification])


    compiled = %{
      notification: notification_entities,
    }


    {:ok, Spark.Dsl.Transformer.persist(dsl_state, :notification_extension_compiled, compiled)}
  end

end
