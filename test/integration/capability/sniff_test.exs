# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.SniffTest do
  @moduledoc "Typed `sniff` against the REAL engine, including the legacy root `sniff/3`."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Sniff, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "turtle text is detected and the result is lossless", %{opts: opts} do
      result = assert_typed_matches_raw("sniff", %{text: sample_turtle()}, opts)
      assert %Result{dialect: "Turtle", engine: engine} = result
      assert is_binary(engine)
      assert result.raw["dialect"] == "Turtle"
    end

    test "string keys, keyword args and the hint are accepted", %{opts: opts} do
      text = "<urn:a:x> <urn:a:p> <urn:a:y> .\n"
      assert {:ok, %Result{dialect: "NTriples"}} = API.sniff(%{"text" => text, "hint" => "ntriples"}, opts)
      assert {:ok, %Result{dialect: "NTriples"}} = API.sniff([text: text], opts)
      assert %Result{dialect: "NTriples"} = API.sniff!(%{text: text}, opts)
    end

    test "the legacy root sniff/3 still returns the raw map for the same text", %{opts: opts} do
      assert {:ok, legacy} = AshGraphLaw.sniff(sample_turtle(), nil, opts)
      assert {:ok, %Result{raw: raw}} = API.sniff(%{text: sample_turtle()}, opts)
      assert legacy == raw
    end

    test "every ok example is admitted and typed", %{opts: opts} do
      for {example, result} <- run_examples("sniff", "ok", opts) do
        assert {:ok, %Result{}} = result, example["id"]
      end
    end
  end

  describe "refusals" do
    test "non-semantic content is an engine refusal with its kind", %{opts: opts} do
      example = example!("sniff.html-refused")
      refusal = assert_refusal(API.sniff(args_of(example), opts), :engine_refused, kind: "NotSemanticContent")
      assert is_map(refusal.raw)
      assert is_binary(refusal.raw["kind"])
    end

    test "a missing text is refused client-side with the exact missing field", %{opts: opts} do
      refusal = assert_refusal(API.sniff(%{}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["text"]
      assert refusal.raw == nil
    end

    test "the engine also refuses the request the client would not build", %{opts: opts} do
      assert {:error, refusal} = AshGraphLaw.call(example!("sniff.missing-text-refused")["request"], opts)
      assert refusal.kind == "Unsupported"
    end
  end
end
