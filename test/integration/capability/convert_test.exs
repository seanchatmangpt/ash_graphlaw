# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.ConvertTest do
  @moduledoc """
  Typed `convert` against the REAL engine: all nine target dialects, determinism of the graph id
  across dialects, and the refusal of a non-RDF target and of a bad source.
  """
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Convert, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "turtle to turtle is typed and lossless", %{opts: opts} do
      result =
        assert_typed_matches_raw("convert", %{text: sample_turtle(), dialect: "turtle", to: "turtle"}, opts)

      assert %Result{text: text, id: id} = result
      assert is_binary(text) and text != ""
      assert is_binary(id)
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = %{text: sample_turtle(), dialect: "turtle", to: "ntriples"}
      assert {:ok, %Result{} = api} = API.convert(args, opts)
      assert {:ok, ^api} = AshGraphLaw.convert(args, opts)
    end
  end

  describe "all nine target dialects" do
    test "the registry lists exactly the nine RDF targets" do
      assert Enum.sort(Enum.map(registry()["rdf_dialects"], & &1["name"])) == Enum.sort(target_dialects())
    end

    test "every target converts, and every output parses back to the same graph id", %{opts: opts} do
      {:ok, %Result{id: base_id}} = API.convert(%{text: sample_turtle(), dialect: "turtle", to: "turtle"}, opts)

      for target <- target_dialects() do
        assert {:ok, %Result{text: text, id: id, raw: %{"ok" => true}}} =
                 API.convert(%{text: sample_turtle(), dialect: "turtle", to: target}, opts),
               "convert to #{target}"

        assert is_binary(text) and text != "", "empty output for #{target}"
        assert id == base_id, "graph id changed for #{target}"
      end
    end

    test "each example dialect target has an ok example", %{opts: opts} do
      for {example, result} <- run_examples("convert", "ok", opts) do
        assert {:ok, %Result{}} = result, example["id"]
      end

      targets = for e <- examples_for("convert"), e["outcome"] == "ok", do: e["request"]["to"]
      assert Enum.sort(targets) == Enum.sort(target_dialects())
    end
  end

  describe "refusals" do
    test "a non-RDF target is refused by the engine as Unsupported", %{opts: opts} do
      example = example!("convert.non-rdf-target-refused")
      assert_refusal(API.convert(args_of(example), opts), :engine_refused, kind: "Unsupported")
    end

    test "a bad source is EngineRejected", %{opts: opts} do
      example = example!("convert.bad-source-refused")
      assert_refusal(API.convert(args_of(example), opts), :engine_refused, kind: "EngineRejected")
    end

    test "missing to is refused client-side", %{opts: opts} do
      refusal = assert_refusal(API.convert(%{text: sample_turtle()}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["to"]
    end

    test "missing text and to are both named, in registry order", %{opts: opts} do
      refusal = assert_refusal(API.convert(%{}, opts), :invalid_capability_request)
      assert Enum.sort(refusal.details["missing"]) == ["text", "to"]
    end
  end
end
