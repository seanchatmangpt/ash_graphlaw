# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Reactor steps.
if Code.ensure_loaded?(Reactor.Step) do
  defmodule AshGraphLaw.Reactor.Capability do
    @moduledoc """
    Generic Reactor step that runs any registry op through the typed capability API.

    ## Options

      * `:op` (required) - a name from `AshGraphLaw.Capability.Registry.names/0`, validated
        when the step runs (an unknown op is `{:error, %AshGraphLaw.Refusal{code: :unknown_capability}}`).
      * every other option is forwarded to the engine call (`:server`, `:timeout`, ...).

    ## Arguments

    The step's arguments are the op's request fields (snake_case atoms). They are
    normalised and validated by the typed API, never by this step.

    ## Result

    `{:ok, %AshGraphLaw.Result.<Op>{}}` (or `%AshGraphLaw.Admitted{}` for `law`) or
    `{:error, %AshGraphLaw.Refusal{}}`.

    No `compensate/4` or `undo/4`: capabilities observe or derive, they never actuate.
    The step never asks Reactor to retry; a refusal is a typed answer.

        step :shapes, AshGraphLaw.Reactor.Capability, op: "shacl" do
          argument :data, input(:data)
          argument :shapes, input(:shapes)
        end
    """

    use Reactor.Step

    alias AshGraphLaw.Capability.{API, Registry}
    alias AshGraphLaw.Refusal

    @impl Reactor.Step
    def run(arguments, context, options) do
      case Keyword.fetch(options, :op) do
        {:ok, op} when is_binary(op) ->
          if op in Registry.names() do
            API.run(op, arguments, AshGraphLaw.Reactor.Hooks.call_opts(context, options))
          else
            {:error, Refusal.build(:unknown_capability, "unknown capability #{inspect(op)}", %{"op" => op})}
          end

        {:ok, other} ->
          {:error,
           Refusal.build(:unknown_capability, "option :op must be a string, got #{inspect(other)}", %{
             "op" => inspect(other)
           })}

        :error ->
          {:error, Refusal.build(:unknown_capability, "option :op is required", %{"op" => nil})}
      end
    end
  end
else
  defmodule AshGraphLaw.Reactor.Capability do
    @moduledoc "Reactor step for any GraphLaw op; the Reactor library is not loaded."
    @spec run(map(), map(), keyword()) :: {:error, String.t()}
    def run(_arguments, _context, _options), do: {:error, "Reactor library is not loaded"}
  end
end
