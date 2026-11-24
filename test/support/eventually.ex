# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Eventually do
  @moduledoc """
  The one audited poll for tests. Time is not a proxy for state: a test waits for an
  observable, bounded by a monotonic deadline, never for a fixed number of loop iterations.

  The only sleep in `test/` that coordinates anything lives here (`@step_ms`), so a sleep gate
  can allowlist this file and nothing else.

    * `await/3` returns the first value for which `ready?` is true, or the last value seen
      when the deadline passes.
    * `await!/3` is `await/3` that flunks when the deadline passes.
    * `hold!/3` asserts an invariant at every step until the deadline (for claims such as
      "the host stays alive across several retry windows").
  """

  import ExUnit.Assertions

  @default_timeout_ms 5_000
  @step_ms 10

  @doc "Poll `fun` until `ready?.(value)` is true or `timeout_ms` elapses; return the last value."
  @spec await((-> term()), (term() -> as_boolean(term())), non_neg_integer()) :: term()
  def await(fun, ready? \\ & &1, timeout_ms \\ @default_timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await(fun, ready?, deadline)
  end

  @doc "Like `await/3` but flunks with `message` when the condition never becomes true."
  @spec await!((-> term()), (term() -> as_boolean(term())), non_neg_integer(), String.t()) :: term()
  def await!(fun, ready? \\ & &1, timeout_ms \\ @default_timeout_ms, message \\ "condition never became true") do
    value = await(fun, ready?, timeout_ms)
    assert ready?.(value), message
    value
  end

  @doc "Run `invariant` (a function that asserts) every step until `duration_ms` has elapsed."
  @spec hold!((-> any()), non_neg_integer()) :: :ok
  def hold!(invariant, duration_ms) do
    deadline = System.monotonic_time(:millisecond) + duration_ms
    do_hold(invariant, deadline)
  end

  defp do_await(fun, ready?, deadline) do
    value = fun.()

    cond do
      ready?.(value) ->
        value

      System.monotonic_time(:millisecond) >= deadline ->
        value

      true ->
        Process.sleep(@step_ms)
        do_await(fun, ready?, deadline)
    end
  end

  defp do_hold(invariant, deadline) do
    invariant.()

    if System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      Process.sleep(@step_ms)
      do_hold(invariant, deadline)
    end
  end
end
