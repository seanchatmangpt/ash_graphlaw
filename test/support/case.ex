# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Case do
  @moduledoc """
  UNSUPPORTED(generator-capability): shared ExUnit case template for ash_graphlaw tests.

  Tests that need the REAL pinned GraphLaw engine are tagged `@tag :wasm` (or
  `@moduletag :wasm`); `test/test_helper.exs` excludes that tag, with a printed reason, when
  the engine is not vendored. `wasm_available?/0` answers the same question at runtime.
  Nothing here stubs the engine.

  `start_host!/1` starts a real `AshGraphLaw.Host` under the test supervisor with a unique
  name. `start_pool!/1` starts the real `AshGraphLaw.Pool`, which registers fixed names
  (`AshGraphLaw.Pool`, `AshGraphLaw.Host`), so a module that starts a pool must be
  `async: false`.
  """

  use ExUnit.CaseTemplate

  alias AshGraphLaw.Test.NTriples

  using do
    quote do
      import AshGraphLaw.Test.Case,
        only: [wasm_available?: 0, wasm_path: 0, start_host!: 0, start_host!: 1, start_pool!: 0, start_pool!: 1, nt: 1]

      alias AshGraphLaw.Refusal
    end
  end

  @doc "The wasm path the library itself would use (opts > env > config > priv)."
  @spec wasm_path() :: String.t()
  def wasm_path, do: AshGraphLaw.WasmConfig.wasm_path([])

  @doc "True when the real engine is present AND passes the engine admission gate (digest pin)."
  @spec wasm_available?() :: boolean()
  def wasm_available? do
    with {:ok, bytes} <- File.read(wasm_path()),
         {:ok, _} <- AshGraphLaw.EngineLoad.admit(bytes, []) do
      true
    else
      _ -> false
    end
  end

  @doc "Starts a real Host under the test supervisor and returns its pid."
  @spec start_host!(keyword()) :: pid()
  def start_host!(opts \\ []) do
    id = {AshGraphLaw.Host, System.unique_integer([:positive])}
    # Unnamed unless the caller names it: two hosts in one test must not both claim the default name.
    spec = Supervisor.child_spec({AshGraphLaw.Host, Keyword.put_new(opts, :name, nil)}, id: id)
    ExUnit.Callbacks.start_supervised!(spec)
  end

  @doc "Starts the real Pool under the test supervisor (fixed names: async: false modules only)."
  @spec start_pool!(keyword()) :: pid()
  def start_pool!(opts \\ []) do
    opts = Keyword.put_new(opts, :size, 2)
    ExUnit.Callbacks.start_supervised!({AshGraphLaw.Pool, opts})
  end

  @doc "Builds N-Triples text from `{s, p, o}` tuples (see `AshGraphLaw.Test.NTriples`)."
  @spec nt([{String.t(), String.t(), term()}]) :: String.t()
  defdelegate nt(triples), to: NTriples, as: :render
end
