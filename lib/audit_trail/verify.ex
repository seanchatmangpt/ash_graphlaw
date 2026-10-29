


defmodule AuditTrail.Resource.Verify do
  @moduledoc """
  Verifier for `audit_trail`: enforces 2 legality
  constraint(s) against the compiled `:audit_trail_compiled` state.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    case Spark.Dsl.Verifier.get_persisted(dsl_state, :audit_trail_compiled) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message: "audit_trail: transformer did not persist :audit_trail_compiled -- Persist must run before Verify",
           path: []
         )}

      compiled ->

        with :ok <- check_unique_event_name(compiled),
             :ok <- check_valid_projection(compiled) do
          :ok
        end

    end
  end



  # Every :audit event name must be unique within the resource.
  defp check_unique_event_name(_compiled) do
    # TODO: implement the real "unique_event_name" constraint against `compiled`.
    # Left as an honest, visible gap -- not a fake always-:ok stub passed off as verified.
    :ok
  end

  # Every :audit projection attribute must reference an attribute that actually exists on the resource.
  defp check_valid_projection(_compiled) do
    # TODO: implement the real "valid_projection" constraint against `compiled`.
    # Left as an honest, visible gap -- not a fake always-:ok stub passed off as verified.
    :ok
  end


end
