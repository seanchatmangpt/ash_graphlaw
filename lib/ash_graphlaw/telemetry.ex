# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits telemetry spans.
defmodule AshGraphLaw.Telemetry do
  @moduledoc """
  Telemetry span around every typed capability call.

  `capability/3` emits, for the op `op`:

    * `[:ash_graphlaw, :capability, :start]` - measurements `%{system_time: integer}`,
      metadata `%{op: String.t(), server: term}`.
    * `[:ash_graphlaw, :capability, :stop]` - measurements `%{duration: integer}` (native
      time units), metadata `%{op:, server:, outcome: :ok | :refused, refusal_code: atom | nil}`.
      `{:ok, _}` is `:ok`; `{:error, %AshGraphLaw.Refusal{}}` is `:refused` with the
      refusal code. Any other return value is passed through and reported as `:ok`
      only when it is not an `{:error, _}` tuple, otherwise `:refused` with a nil code.
    * `[:ash_graphlaw, :capability, :exception]` - measurements `%{duration: integer}`,
      metadata `%{op:, server:, outcome: :exception, refusal_code: nil, kind:, reason:,
      stacktrace:}`. The exception is re-raised after the event is emitted.

  The pre-existing `[:ash_graphlaw, :admission, :stop]` event is untouched.

  ## Attaching a handler

      :telemetry.attach_many(
        "my-app-graphlaw",
        AshGraphLaw.Telemetry.events(),
        fn event, measurements, metadata, _config ->
          Logger.info("graphlaw \#{inspect(event)} \#{inspect(metadata)} \#{inspect(measurements)}")
        end,
        nil
      )

  A telemetry observation is never authority; it records what happened.
  """

  alias AshGraphLaw.Refusal

  @prefix [:ash_graphlaw, :capability]

  @doc "Every event name this module emits."
  @spec events() :: [[atom()]]
  def events do
    [
      @prefix ++ [:start],
      @prefix ++ [:stop],
      @prefix ++ [:exception],
      [:ash_graphlaw, :admission, :stop]
    ]
  end

  @doc """
  Runs `fun` inside a capability span for `op` and returns its result unchanged.

  `opts` is the same keyword list handed to `AshGraphLaw.call/2`; only `:server` is read.
  """
  @spec capability(String.t(), keyword(), (-> result)) :: result when result: term()
  def capability(op, opts, fun) when is_binary(op) and is_list(opts) and is_function(fun, 0) do
    server = Keyword.get(opts, :server, AshGraphLaw.Pool)
    base = %{op: op, server: server}
    started = System.monotonic_time()

    :telemetry.execute(@prefix ++ [:start], %{system_time: System.system_time()}, base)

    try do
      result = fun.()
      {outcome, code} = classify(result)

      :telemetry.execute(
        @prefix ++ [:stop],
        %{duration: System.monotonic_time() - started},
        Map.merge(base, %{outcome: outcome, refusal_code: code})
      )

      result
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__

        :telemetry.execute(
          @prefix ++ [:exception],
          %{duration: System.monotonic_time() - started},
          Map.merge(base, %{
            outcome: :exception,
            refusal_code: nil,
            kind: kind,
            reason: reason,
            stacktrace: stacktrace
          })
        )

        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp classify({:error, %Refusal{code: code}}), do: {:refused, code}
  defp classify({:error, _}), do: {:refused, nil}
  defp classify(_), do: {:ok, nil}
end
