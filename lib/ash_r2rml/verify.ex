


defmodule AshR2RML.Resource.Verify do
  @moduledoc """
  Verifier for `ash_r2rml`: enforces 0 legality
  constraint(s) against the compiled `:ash_r2rml_compiled` state.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    case Spark.Dsl.Verifier.get_persisted(dsl_state, :ash_r2rml_compiled) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message: "ash_r2rml: transformer did not persist :ash_r2rml_compiled -- Persist must run before Verify",
           path: []
         )}

      _compiled ->

        # No aex:Verifier rows on this spec -- a legal, unconstrained extension.
        # (A `with` with zero clauses is invalid Elixir, so this is a plain :ok,
        # not an empty `with ... do :ok end`; the persisted state is bound as
        # `_compiled` because nothing reads it.)
        :ok

    end
  end




end
