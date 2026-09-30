# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Reactor steps.
# Reactor is an OPTIONAL dependency: each step file wraps its module in
# `if Code.ensure_loaded?(Reactor.Step)` and otherwise defines an inert stub that
# returns `{:error, "Reactor library is not loaded"}` instead of failing compilation.
defmodule AshGraphLaw.Reactor do
  @moduledoc """
  Reactor integration for typed GraphLaw capabilities.

  Steps (available when the optional `:reactor` dependency is loaded):

    * `AshGraphLaw.Reactor.Hooks` - runs a knowledge-hook pack over data.
    * `AshGraphLaw.Reactor.Capability` - runs any registry op (`option :op`).

  Neither step actuates anything: the engine only observes and derives, so no
  `compensate/4` or `undo/4` is defined and both steps declare `retry: never`
  semantics (a refusal is a typed answer, not a transient fault).

  `available?/0` reports whether the steps are real.
  """

  @doc "True when the Reactor library is loaded and the steps are real."
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Reactor.Step)
end
