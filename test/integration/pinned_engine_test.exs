# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.PinnedEngineTest do
  @moduledoc """
  The engine pin, asserted rather than skipped.

  `test/test_helper.exs` excludes `:wasm` tests when the engine is not vendored, which by itself
  would let a green run say nothing about the pinned engine. This file closes that gap in three
  layers:

    * wasm-free: the manifest pins graphlaw `v26.9.28` to a fixed SHA-256, and the pin resolvers
      keep it fixed against the environment;
    * the gate: with `ASH_GRAPHLAW_REQUIRE_ENGINE=1` an unvendored engine is a FAILURE, never a
      skip. The gate test is deliberately untagged, so the `:wasm` exclusion cannot hide it;
    * `:wasm`: the vendored bytes hash to the pin and a host really runs them.

  Without `ASH_GRAPHLAW_REQUIRE_ENGINE=1` and without a vendored engine, the gate prints
  `UNKNOWN` for the engine claims; it never reports them as observed.

  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{EngineLoad, Host, Refusal, WasmConfig}

  @pin "30f6bc6eca9d125fe805f4c2643818ebb0a1471edec75ed0ed989c734397c645"
  @tag_url "https://github.com/seanchatmangpt/graphlaw/releases/download/v26.9.28/graphlaw.wasm"
  @require_env "ASH_GRAPHLAW_REQUIRE_ENGINE"

  defp sha(bin), do: Base.encode16(:crypto.hash(:sha256, bin), case: :lower)
  defp require_engine?, do: System.get_env(@require_env) in ["1", "true"]

  describe "the pin (no engine needed)" do
    test "the manifest pins graphlaw v26.9.28 to the fixed digest and release URL" do
      assert {:ok, manifest} = WasmConfig.manifest()
      assert manifest["graphlaw_version"] == "26.9.28"
      assert get_in(manifest, ["artifact", "sha256"]) == @pin
      assert get_in(manifest, ["artifact", "url"]) == @tag_url
      assert get_in(manifest, ["artifact", "file"]) == "graphlaw.wasm"
      assert manifest["abi_version"] == AshGraphLaw.ABI.version()
    end

    test "every resolver agrees on the same pin" do
      assert WasmConfig.pinned_sha256() == @pin
      assert EngineLoad.pinned_sha256() == @pin
      assert WasmConfig.expected_sha256([]) == @pin
      assert WasmConfig.expected_sha256(wasm_path: WasmConfig.vendored_path()) == @pin
    end

    test "positive control: an explicit foreign path is unpinned, so the pin assertion is not vacuous" do
      assert WasmConfig.expected_sha256(wasm_path: "/nonexistent/other.wasm") == :unpinned
      assert WasmConfig.expected_sha256(wasm_path: "/nonexistent/other.wasm") != @pin
    end

    test "the environment cannot swap the pin, only the path" do
      previous = System.get_env("GRAPHLAW_WASM_PATH")
      System.put_env("GRAPHLAW_WASM_PATH", "/nonexistent/from_env.wasm")

      on_exit(fn ->
        if previous, do: System.put_env("GRAPHLAW_WASM_PATH", previous), else: System.delete_env("GRAPHLAW_WASM_PATH")
      end)

      assert WasmConfig.wasm_path([]) == "/nonexistent/from_env.wasm"
      assert WasmConfig.expected_sha256([]) == @pin
    end

    test "bytes that hash to anything but the pin never pass the engine gate" do
      bytes = <<0, 97, 115, 109, 1, 0, 0, 0>>
      refute sha(bytes) == @pin

      assert {:error, %Refusal{code: :wasm_digest_mismatch, class: :refused_identity}} = EngineLoad.admit(bytes, [])
    end
  end

  describe "the gate" do
    test "ASH_GRAPHLAW_REQUIRE_ENGINE=1 turns an unvendored or foreign engine into a failure, not a skip" do
      path = wasm_path()

      case File.read(path) do
        {:ok, bytes} ->
          # a vendored engine must be THE pinned engine, whatever the environment says
          assert sha(bytes) == @pin, "#{path} hashes to #{sha(bytes)}, not the pin #{@pin}"
          assert {:ok, %{wasm_sha256: @pin}} = EngineLoad.admit(bytes, [])
          assert wasm_available?()

          if require_engine?() do
            refute :wasm in Keyword.get(ExUnit.configuration(), :exclude, []),
                   "#{@require_env}=1 but :wasm tests are excluded from this run"
          end

        {:error, reason} ->
          if require_engine?() do
            flunk("""
            #{@require_env}=1 but the pinned engine is not readable at #{path} (#{inspect(reason)}).
            Vendor it with `mix ash_graphlaw.vendor` (sha256 #{@pin}); :wasm tests must run, not skip.
            """)
          else
            IO.puts(
              :stderr,
              "[pinned_engine] UNKNOWN: no engine at #{path}; engine claims are unobserved in this run " <>
                "(set #{@require_env}=1 to make this a failure)"
            )

            refute wasm_available?()
          end
      end
    end
  end

  describe "the vendored engine (real)" do
    @describetag :wasm

    test "the vendored bytes hash to the pin and a host runs exactly those bytes" do
      bytes = File.read!(wasm_path())
      assert sha(bytes) == @pin

      host = start_host!([])
      assert {:ok, %{wasm_sha256: digest}} = Host.info(host)
      assert digest == @pin
      assert {:ok, %{"ok" => true, "abi" => abi}} = Host.request(host, %{"op" => "capabilities"})
      assert abi == AshGraphLaw.ABI.version()
    end

    test "flipping one byte of the real engine is refused :wasm_digest_mismatch" do
      bytes = File.read!(wasm_path())
      # positive control: the untouched bytes are admitted under the pin
      assert {:ok, %{wasm_sha256: @pin}} = EngineLoad.admit(bytes, [])

      pos = div(byte_size(bytes), 2)
      <<head::binary-size(pos), byte, tail::binary>> = bytes
      flipped = <<head::binary, Bitwise.bxor(byte, 1), tail::binary>>
      refute sha(flipped) == @pin

      assert {:error, %Refusal{code: :wasm_digest_mismatch, class: :refused_identity}} = EngineLoad.admit(flipped, [])
    end

    test "a host started on the flipped bytes under the pin answers with the refusal and stays alive" do
      bytes = File.read!(wasm_path())
      good = start_host!(bytes: bytes)
      assert {:ok, %{"ok" => true}} = Host.request(good, %{"op" => "capabilities"})

      pos = div(byte_size(bytes), 3)
      <<head::binary-size(pos), byte, tail::binary>> = bytes
      flipped = <<head::binary, Bitwise.bxor(byte, 1), tail::binary>>

      bad = start_host!(bytes: flipped, expected_sha256: @pin)
      assert {:error, %Refusal{code: :wasm_digest_mismatch}} = Host.request(bad, %{"op" => "capabilities"})
      assert Process.alive?(bad)
    end
  end
end
