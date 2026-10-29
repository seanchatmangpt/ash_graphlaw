


defmodule NotificationExtension.Resource.Verify do
  @moduledoc """
  Verifier for `notification_extension`: enforces 0 legality
  constraint(s) against the compiled `:notification_extension_compiled` state.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    case Spark.Dsl.Verifier.get_persisted(dsl_state, :notification_extension_compiled) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message: "notification_extension: transformer did not persist :notification_extension_compiled -- Persist must run before Verify",
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
