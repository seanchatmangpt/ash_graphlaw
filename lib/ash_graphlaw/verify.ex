


defmodule AshGraphLaw.Resource.Verify do
  @moduledoc """
  Verifier for `ash_graphlaw`: enforces 0 legality
  constraint(s) against the compiled `:ash_graphlaw_compiled` state.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    case Spark.Dsl.Verifier.get_persisted(dsl_state, :ash_graphlaw_compiled) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message: "ash_graphlaw: transformer did not persist :ash_graphlaw_compiled -- Persist must run before Verify",
           path: []
         )}

      compiled ->

        # ash_r2rml's exact 2-branch shape (resource.ex:492-511): nil-check stays
        # inline (above), business validation delegates to a separate module's
        # validate function instead of an inline per-verifier chain.
        case AshGraphLaw.Contract.validate(compiled) do
          :ok ->
            :ok

          {:error, refusals} ->
            {:error,
             Spark.Error.DslError.exception(
               message: Enum.map_join(refusals, "; ", &"#{&1.code}: #{&1.detail}"),
               path: []
             )}
        end

    end
  end


end
