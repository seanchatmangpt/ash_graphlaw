# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.N3Test do
  @moduledoc "Typed `n3` against the REAL engine: derived facts stay the engine's `any` value."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.N3, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "a rule derives facts and derived is carried untouched", %{opts: opts} do
      result = assert_typed_matches_raw("n3", args_of(example!("n3.reason")), opts)
      assert %Result{derived: derived} = result
      assert derived == result.raw["derived"]
      refute is_nil(derived)
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = args_of(example!("n3.reason"))
      assert {:ok, %Result{} = api} = API.n3(args, opts)
      assert {:ok, ^api} = AshGraphLaw.n3(args, opts)
    end

    test "text with no rules still answers ok", %{opts: opts} do
      assert {:ok, %Result{raw: %{"ok" => true}}} = API.n3(%{text: "@prefix : <https://e/> . :a :b :c ."}, opts)
    end
  end

  describe "refusals" do
    test "an N3 syntax error is an engine refusal", %{opts: opts} do
      assert_refusal(API.n3(args_of(example!("n3.syntax-refused")), opts), :engine_refused, kind: "EngineRejected")
    end

    test "missing text is refused client-side", %{opts: opts} do
      refusal = assert_refusal(API.n3(%{}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["text"]
    end

    test "the engine refuses the same missing text as Unsupported", %{opts: opts} do
      assert {:error, refusal} = AshGraphLaw.call(example!("n3.missing-text-refused")["request"], opts)
      assert refusal.kind == "Unsupported"
    end
  end
end
