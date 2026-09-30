# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Reactor steps.
if Code.ensure_loaded?(Reactor.Step) do
  defmodule AshGraphLaw.Reactor.Hooks do
    @moduledoc """
    Reactor step that runs a knowledge-hook pack over data through the real engine.

    ## Arguments

      * `:pack` - the hook pack (text or `%{text:, dialect:}` data spec).
      * `:data` - the data to fire hooks over (same forms).

    ## Options

    Any option accepted by `AshGraphLaw.call/2` (`:server`, `:timeout`, `:fuel`, ...).

    ## Result

    `{:ok, %AshGraphLaw.Result.Hooks{}}` or `{:error, %AshGraphLaw.Refusal{}}`.

    ## Compensation and retry

    Hooks only derive quads and record firings; nothing is actuated, so there is
    nothing to undo and no `compensate/4` is defined. A refusal is a typed answer,
    not a transient fault, so the step never asks Reactor to retry.

        step :fire, AshGraphLaw.Reactor.Hooks do
          argument :pack, input(:pack)
          argument :data, input(:data)
        end

    A hook firing is an observation, never authority.
    """

    use Reactor.Step

    alias AshGraphLaw.{Capability.API, Refusal}

    @impl Reactor.Step
    def run(arguments, context, options) do
      case arguments do
        %{pack: pack, data: data} ->
          API.hooks(%{pack: pack, data: data}, call_opts(context, options))

        _ ->
          {:error,
           Refusal.build(
             :invalid_capability_request,
             "hooks step requires :pack and :data arguments",
             %{"missing" => missing(arguments)}
           )}
      end
    end

    defp missing(arguments) do
      for {name, key} <- [{"pack", :pack}, {"data", :data}], not Map.has_key?(arguments, key), do: name
    end

    @doc false
    @spec call_opts(map(), keyword()) :: keyword()
    def call_opts(context, options) do
      from_context =
        case context do
          %{private: %{ash_graphlaw_opts: opts}} when is_list(opts) -> opts
          _ -> []
        end

      Keyword.merge(from_context, Keyword.drop(options, [:op]))
    end
  end
else
  defmodule AshGraphLaw.Reactor.Hooks do
    @moduledoc "Reactor step for GraphLaw hooks; the Reactor library is not loaded."
    @spec run(map(), map(), keyword()) :: {:error, String.t()}
    def run(_arguments, _context, _options), do: {:error, "Reactor library is not loaded"}
  end
end
