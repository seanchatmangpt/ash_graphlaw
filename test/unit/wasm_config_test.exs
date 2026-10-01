# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.WasmConfigTest do
  # async: false -- resolution reads the process environment and the application env,
  # both node-global. The test restores both in on_exit.
  use ExUnit.Case, async: false

  alias AshGraphLaw.WasmConfig

  # The pin is read from the shipped manifest; one literal control (below) guards the manifest itself.
  @literal_pin "7bb2a7e5ebcef7584b0b960451272d56fa75414d76a12138d41e8973e126eee0"
  @pin "priv/graphlaw/MANIFEST.json" |> File.read!() |> Jason.decode!() |> get_in(["artifact", "sha256"])
  @env "GRAPHLAW_WASM_PATH"

  setup do
    prior_env = System.get_env(@env)
    prior_app = Application.fetch_env(:ash_graphlaw, :wasm_path)

    System.delete_env(@env)
    Application.delete_env(:ash_graphlaw, :wasm_path)

    on_exit(fn ->
      if prior_env, do: System.put_env(@env, prior_env), else: System.delete_env(@env)

      case prior_app do
        {:ok, value} -> Application.put_env(:ash_graphlaw, :wasm_path, value)
        :error -> Application.delete_env(:ash_graphlaw, :wasm_path)
      end
    end)

    dir = Path.join(System.tmp_dir!(), "ash_graphlaw_wasm_config_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    paths =
      for name <- ~w(opts env app) do
        path = Path.join(dir, "#{name}.wasm")
        File.write!(path, "bytes for #{name}")
        {String.to_atom(name), path}
      end

    {:ok, Map.new(paths)}
  end

  @vendored Application.app_dir(:ash_graphlaw, "priv/graphlaw/graphlaw.wasm")

  test "literal-pin control: the manifest pin is the GraphLaw v26.9.29 release asset digest" do
    assert @pin == @literal_pin
    assert WasmConfig.pinned_sha256() == @literal_pin
  end

  describe "wasm_path/1 resolution order" do
    test "positive control: with nothing set, the vendored priv path is used" do
      assert WasmConfig.wasm_path([]) == @vendored
      assert String.ends_with?(WasmConfig.wasm_path([]), "priv/graphlaw/graphlaw.wasm")
    end

    test "application config beats the vendored default", %{app: app} do
      Application.put_env(:ash_graphlaw, :wasm_path, app)
      assert WasmConfig.wasm_path([]) == app
    end

    test "the environment variable beats application config", %{app: app, env: env} do
      Application.put_env(:ash_graphlaw, :wasm_path, app)
      System.put_env(@env, env)
      assert WasmConfig.wasm_path([]) == env
    end

    test "an explicit option beats the environment variable and application config", %{app: app, env: env, opts: opts} do
      Application.put_env(:ash_graphlaw, :wasm_path, app)
      System.put_env(@env, env)
      assert WasmConfig.wasm_path(wasm_path: opts) == opts
    end

    test "an empty option list falls through every level, one at a time", %{app: app, env: env} do
      assert WasmConfig.wasm_path([]) == @vendored
      Application.put_env(:ash_graphlaw, :wasm_path, app)
      assert WasmConfig.wasm_path([]) == app
      System.put_env(@env, env)
      assert WasmConfig.wasm_path([]) == env
    end
  end

  describe "pinned_sha256/0" do
    test "is the GraphLaw v26.9.29 release asset digest" do
      assert WasmConfig.pinned_sha256() == @pin
    end

    test "is 64 lowercase hex characters" do
      assert WasmConfig.pinned_sha256() =~ ~r/\A[0-9a-f]{64}\z/
    end
  end

  describe "expected_sha256/1 (SC-04: the environment cannot swap the admission engine)" do
    test "positive control: the default is the pin" do
      assert WasmConfig.expected_sha256([]) == @pin
    end

    test "an explicit path that differs from the vendored path is :unpinned", %{opts: opts} do
      assert WasmConfig.expected_sha256(wasm_path: opts) == :unpinned
    end

    test "an explicit path equal to the vendored path stays pinned" do
      assert WasmConfig.expected_sha256(wasm_path: @vendored) == @pin
    end

    test "an explicit expected_sha256 is honoured for an explicit path", %{opts: opts} do
      digest = String.duplicate("ab", 32)
      assert WasmConfig.expected_sha256(wasm_path: opts, expected_sha256: digest) == digest
    end

    test "a path supplied by the environment variable stays pinned", %{env: env} do
      System.put_env(@env, env)
      assert WasmConfig.wasm_path([]) == env
      assert WasmConfig.expected_sha256([]) == @pin
    end

    test "a path supplied by application config stays pinned", %{app: app} do
      Application.put_env(:ash_graphlaw, :wasm_path, app)
      assert WasmConfig.wasm_path([]) == app
      assert WasmConfig.expected_sha256([]) == @pin
    end

    test "an environment path cannot un-pin, even when an option elsewhere is absent", %{env: env, app: app} do
      System.put_env(@env, env)
      Application.put_env(:ash_graphlaw, :wasm_path, app)
      assert WasmConfig.expected_sha256([]) == @pin
    end
  end

  describe "limits/1" do
    test "positive control: the documented defaults" do
      limits = Map.new(WasmConfig.limits([]))

      assert limits.timeout_ms == 5_000
      # fuel follows the deadline: timeout_ms * fuel_per_ms
      assert limits.fuel_per_ms == 1_000_000
      assert limits.fuel == 5_000_000_000
      assert limits.instantiate_fuel == 1_000_000_000
      assert limits.memory_limit_bytes == 268_435_456
      assert limits.recycle_bytes == 134_217_728
      assert limits.max_queue == 64
      assert limits.max_response_bytes == 33_554_432
      assert limits.table_elements == 100_000
      assert limits.instances == 10
      assert limits.tables == 10
      assert limits.memories == 4
    end

    test "fuel is derived from the timeout unless given explicitly" do
      assert WasmConfig.limits(timeout_ms: 250).fuel == 250_000_000
      assert WasmConfig.limits(timeout_ms: 250, fuel_per_ms: 10).fuel == 2_500
      assert WasmConfig.limits(timeout_ms: 250, fuel: 1_234).fuel == 1_234
    end

    test "the response cap and the store limits are overridable and stay positive" do
      limits = WasmConfig.limits(max_response_bytes: 1_024, table_elements: 7, instances: 2, tables: 3, memories: 1)
      assert %{max_response_bytes: 1_024, table_elements: 7, instances: 2, tables: 3, memories: 1} = limits

      # a non-positive override is ignored, never applied
      assert WasmConfig.limits(max_response_bytes: 0).max_response_bytes == 33_554_432
      assert WasmConfig.limits(instances: -1).instances == 10
    end

    test "options override only the named limit" do
      limits = Map.new(WasmConfig.limits(max_queue: 3, timeout_ms: 250))

      assert limits.max_queue == 3
      assert limits.timeout_ms == 250
      assert limits.fuel == 250_000_000
      assert limits.memory_limit_bytes == 268_435_456
    end
  end

  describe "manifest/0" do
    test "reads the generated priv/graphlaw/MANIFEST.json into a map" do
      assert {:ok, manifest} = WasmConfig.manifest()
      assert is_map(manifest)
      assert map_size(manifest) > 0
    end
  end
end
