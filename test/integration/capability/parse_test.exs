# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.ParseTest do
  @moduledoc "Typed `parse` against the REAL engine: dialect, quad count, syntax-check mode, refusals."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Parse, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "turtle parses to a typed result equal to the engine answer", %{opts: opts} do
      result = assert_typed_matches_raw("parse", %{text: sample_turtle(), dialect: "turtle"}, opts)
      assert %Result{dialect: "Turtle"} = result
      assert result.quads == 4
      assert is_binary(result.id)
    end

    test "the dialect can be sniffed instead of given", %{opts: opts} do
      assert {:ok, %Result{dialect: "Turtle", quads: 4}} = API.parse(%{text: sample_turtle()}, opts)
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = %{text: sample_turtle(), dialect: "turtle"}
      assert {:ok, %Result{} = api} = API.parse(args, opts)
      assert {:ok, ^api} = AshGraphLaw.parse(args, opts)
      assert ^api = AshGraphLaw.parse!(args, opts)
    end

    test "every ok example is typed and lossless", %{opts: opts} do
      for {example, result} <- run_examples("parse", "ok", opts) do
        assert {:ok, %Result{raw: %{"ok" => true}}} = result, example["id"]
      end
    end
  end

  describe "refusals" do
    test "invalid syntax is an engine refusal (EngineRejected) with raw intact", %{opts: opts} do
      refusal =
        assert_refusal(API.parse(args_of(example!("parse.turtle-invalid-refused")), opts), :engine_refused,
          kind: "EngineRejected"
        )

      assert is_binary(refusal.raw["kind"])
    end

    test "an unknown dialect is refused by the engine as Unsupported (enum is informational)", %{opts: opts} do
      example = example!("parse.unknown-dialect-refused")
      assert_refusal(API.parse(args_of(example), opts), :engine_refused, kind: "Unsupported")
    end

    test "missing text is a client refusal naming the field", %{opts: opts} do
      refusal = assert_refusal(API.parse(%{dialect: "turtle"}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["text"]
    end

    test "bang form raises for an engine refusal", %{opts: opts} do
      assert_raise AshGraphLaw.Error.Refused, fn ->
        API.parse!(args_of(example!("parse.turtle-invalid-refused")), opts)
      end
    end
  end
end
