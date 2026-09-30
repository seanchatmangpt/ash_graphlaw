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

  ## Tags

    * `:wasm` - the test needs the REAL vendored engine. Excluded (with a printed reason) by
      `test/test_helper.exs` when the engine is absent or fails the digest pin.
    * `:slow` - long-running test. Excluded by default; run with `mix test --include slow`.

  `require_engine!/0` is the fail-closed companion for `:wasm` tests: when the engine is not
  usable it raises `ExUnit.AssertionError` if `ASH_GRAPHLAW_REQUIRE_ENGINE` is set to a truthy
  value (CI sets it, so an unvendored engine can never pass silently), and otherwise returns
  `:skip`-style `false` so the caller can decide.
  """

  use ExUnit.CaseTemplate

  alias AshGraphLaw.Test.NTriples

  using do
    quote do
      import AshGraphLaw.Test.Case,
        only: [
          wasm_available?: 0,
          wasm_path: 0,
          start_host!: 0,
          start_host!: 1,
          start_pool!: 0,
          start_pool!: 1,
          nt: 1,
          require_engine!: 0,
          manifest: 0,
          manifest_pin: 0
        ]

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

  @doc """
  Decodes the shipped `priv/graphlaw/MANIFEST.json` (the generated pin table).

  Tests read the pin from here so a legitimate ontology-driven engine bump does not require
  hand-editing every assertion; one literal-pin control per suite guards the manifest itself.
  """
  @spec manifest() :: map()
  def manifest do
    Path.join(File.cwd!(), "priv/graphlaw/MANIFEST.json") |> File.read!() |> Jason.decode!()
  end

  @doc "The wasm SHA-256 recorded in the manifest."
  @spec manifest_pin() :: String.t()
  def manifest_pin, do: manifest()["artifact"]["sha256"]

  @doc """
  Asserts the real engine is usable when `ASH_GRAPHLAW_REQUIRE_ENGINE` is truthy
  (`1`, `true`, `yes`); returns whether the engine is available otherwise.
  """
  @spec require_engine!() :: boolean()
  def require_engine! do
    available = wasm_available?()

    if not available and System.get_env("ASH_GRAPHLAW_REQUIRE_ENGINE") in ~w(1 true yes) do
      raise ExUnit.AssertionError,
        message:
          "ASH_GRAPHLAW_REQUIRE_ENGINE is set but the engine at #{wasm_path()} is not usable; " <>
            "run `mix ash_graphlaw.vendor`"
    end

    available
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
