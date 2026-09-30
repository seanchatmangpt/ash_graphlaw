# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.ShaclTest do
  @moduledoc "Typed `shacl` against the REAL engine: conforming and violating data, engine refusals."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Shacl, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "conforming data yields conforms: true, no results, lossless raw", %{opts: opts} do
      result = assert_typed_matches_raw("shacl", args_of(example!("shacl.conforming")), opts)
      assert %Result{conforms: true, results: []} = result
    end

    test "violating data yields conforms: false and result objects that stay plain maps", %{opts: opts} do
      result = assert_typed_matches_raw("shacl", args_of(example!("shacl.violating")), opts)
      assert %Result{conforms: false, results: [first | _]} = result
      assert is_map(first) and not is_struct(first)
      assert first in result.raw["results"]
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = args_of(example!("shacl.violating"))
      assert {:ok, %Result{} = api} = API.shacl(args, opts)
      assert {:ok, ^api} = AshGraphLaw.shacl(args, opts)
      assert ^api = AshGraphLaw.shacl!(args, opts)
    end

    test "every ok example is typed", %{opts: opts} do
      for {example, result} <- run_examples("shacl", "ok", opts) do
        assert {:ok, %Result{conforms: conforms}} = result, example["id"]
        assert is_boolean(conforms)
      end
    end
  end

  describe "refusals" do
    test "unparsable shapes are an engine refusal", %{opts: opts} do
      assert_refusal(API.shacl(args_of(example!("shacl.bad-shapes-refused")), opts), :engine_refused,
        kind: "EngineRejected"
      )
    end

    test "missing shapes is refused client-side and by the engine", %{opts: opts} do
      example = example!("shacl.missing-shapes-refused")
      refusal = assert_refusal(API.shacl(args_of(example), opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["shapes"]
      assert {:error, engine} = AshGraphLaw.call(example["request"], opts)
      assert engine.kind == "Unsupported"
    end
  end
end
