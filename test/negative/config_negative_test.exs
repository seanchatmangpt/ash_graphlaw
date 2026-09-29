# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits negative courts.

defmodule AshGraphLaw.Negative.ConfigNegativeTest do
  @moduledoc """
  Negative court for engine pinning.

  The environment (`GRAPHLAW_WASM_PATH`) and application config may redirect where the
  engine bytes are read from, but never which digest they must match: a redirected engine
  is still judged against the manifest pin. Only an explicit `:wasm_path` option that
  differs from the vendored path opts out, and it does so visibly in code.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.{EngineLoad, Host, Refusal, WasmConfig}
  alias AshGraphLaw.Test.WasmFixtures

  @env "GRAPHLAW_WASM_PATH"

  setup do
    old_env = System.get_env(@env)
    old_cfg = Application.fetch_env(:ash_graphlaw, :wasm_path)
    EngineLoad.purge_cache()

    on_exit(fn ->
      if old_env, do: System.put_env(@env, old_env), else: System.delete_env(@env)

      case old_cfg do
        {:ok, value} -> Application.put_env(:ash_graphlaw, :wasm_path, value)
        :error -> Application.delete_env(:ash_graphlaw, :wasm_path)
      end

      EngineLoad.purge_cache()
    end)

    System.delete_env(@env)
    Application.delete_env(:ash_graphlaw, :wasm_path)

    dir = Path.join(System.tmp_dir!(), "ash_graphlaw_cfg_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "foreign.wasm")
    File.write!(path, WasmFixtures.admissible_surface())
    %{foreign: path}
  end

  # The literal pin (ontology.ttl glx:wasmSha256). Every equality below compares against THIS, never
  # against `WasmConfig.pinned_sha256()`: that function returns nil for an unusable manifest, and
  # `nil == nil` would pass vacuously.
  @pin "30f6bc6eca9d125fe805f4c2643818ebb0a1471edec75ed0ed989c734397c645"

  test "positive control: the pin is a 64-char lowercase hex digest and the default is pinned" do
    assert WasmConfig.pinned_sha256() == @pin
    assert WasmConfig.expected_sha256([]) == @pin
    assert WasmConfig.wasm_path([]) == WasmConfig.vendored_path()
  end

  test "an environment-redirected path is used for bytes but stays pinned", %{foreign: foreign} do
    System.put_env(@env, foreign)

    assert WasmConfig.wasm_path([]) == foreign
    assert WasmConfig.expected_sha256([]) == @pin
  end

  test "application-config redirection stays pinned too", %{foreign: foreign} do
    Application.put_env(:ash_graphlaw, :wasm_path, foreign)

    assert WasmConfig.wasm_path([]) == foreign
    assert WasmConfig.expected_sha256([]) == @pin
  end

  test "the environment cannot swap the admission engine: foreign bytes fail the digest pin", %{foreign: foreign} do
    bytes = File.read!(foreign)
    digest = WasmFixtures.sha256(bytes)

    # control: with the foreign digest as the explicit pin the same bytes are admitted
    assert {:ok, _} = EngineLoad.admit(bytes, expected_sha256: digest)
    EngineLoad.purge_cache()

    System.put_env(@env, foreign)
    redirected = File.read!(WasmConfig.wasm_path([]))
    assert redirected == bytes

    assert {:error, %Refusal{code: :wasm_digest_mismatch} = refusal} = EngineLoad.admit(redirected, [])
    assert refusal.details.expected == @pin
    assert refusal.details.actual == digest
  end

  test "a host started against an env-redirected foreign engine is unavailable, not running it", %{foreign: foreign} do
    System.put_env(@env, foreign)
    host = start_host!(name: nil)

    refute Host.available?(host, 5_000)
    assert {:error, %Refusal{code: :wasm_digest_mismatch}} = Host.request(host, %{"op" => "capabilities"})
  end

  test "an explicit differing :wasm_path is unpinned; an explicit :expected_sha256 wins", %{foreign: foreign} do
    assert WasmConfig.expected_sha256(wasm_path: foreign) == :unpinned

    digest = String.duplicate("d", 64)
    assert WasmConfig.expected_sha256(wasm_path: foreign, expected_sha256: digest) == digest
    assert WasmConfig.expected_sha256(expected_sha256: digest) == digest
  end

  test "an explicit :wasm_path equal to the vendored path stays pinned" do
    assert WasmConfig.expected_sha256(wasm_path: WasmConfig.vendored_path()) == @pin

    assert WasmConfig.expected_sha256(wasm_path: Path.join([WasmConfig.vendored_path(), "..", "graphlaw.wasm"])) ==
             @pin
  end

  test "an empty explicit path or empty env does not opt out of the pin" do
    System.put_env(@env, "")
    assert WasmConfig.expected_sha256([]) == @pin
    assert WasmConfig.wasm_path([]) == WasmConfig.vendored_path()
    assert WasmConfig.expected_sha256(wasm_path: "") == @pin
  end
end
