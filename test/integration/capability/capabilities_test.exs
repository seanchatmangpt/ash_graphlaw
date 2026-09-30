# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.CapabilitiesTest do
  @moduledoc """
  Typed `capabilities` against the REAL engine: result fields, raw losslessness, legacy root
  behavior, and the client-side refusals of a request that takes no arguments.
  """
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Capability.Registry
  alias AshGraphLaw.Result.Capabilities, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "typed result mirrors the engine answer and keeps it whole in :raw", %{opts: opts} do
      result = assert_typed_matches_raw("capabilities", %{}, opts)

      assert %Result{abi: 1, abi_version: 1} = result
      assert is_binary(result.crate)
      assert is_list(result.authorities)
      assert result.ops == op_names()
      assert result.rdf_dialects == Registry.rdf_dialects()
      assert result.other_dialects == Registry.other_dialects()
    end

    test "the example runs through the API, the module and the bang form", %{opts: opts} do
      example = example!("capabilities.default")
      assert {:ok, %Result{} = a} = API.capabilities(args_of(example), opts)
      assert {:ok, %Result{} = b} = via_module("capabilities", args_of(example), opts)
      assert a == b
      assert %Result{} = API.capabilities!(%{}, opts)
    end

    test "registry_sha256, when the engine reports it, equals the vendored registry digest", %{opts: opts} do
      {:ok, %Result{} = result} = API.capabilities(%{}, opts)

      if is_binary(result.registry_sha256) do
        assert result.registry_sha256 == Registry.digest()
        assert result.registry_schema == Registry.schema()
      else
        assert result.registry_sha256 == nil
      end
    end

    test "the legacy root capabilities/1 keeps returning the raw map", %{opts: opts} do
      assert {:ok, legacy} = AshGraphLaw.capabilities(opts)
      assert is_map(legacy) and not is_struct(legacy)
      assert {:ok, %Result{raw: raw}} = API.capabilities(%{}, opts)
      assert legacy == raw
    end
  end

  describe "refusals" do
    test "an op key is never accepted from args", %{opts: opts} do
      refusal =
        assert_refusal(API.capabilities(%{"op" => "sniff"}, opts), :invalid_capability_request)

      assert refusal.details["unknown_keys"] == ["op"]
    end

    test "unknown args refuse before the engine is reached", %{opts: opts} do
      refusal = assert_refusal(API.capabilities(%{surprise: 1}, opts), :invalid_capability_request)
      assert refusal.details["unknown_keys"] == ["surprise"]
    end

    test "bang form raises the wrapped refusal", %{opts: opts} do
      assert_raise AshGraphLaw.Error.Refused, fn -> API.capabilities!(%{surprise: 1}, opts) end
    end
  end
end
