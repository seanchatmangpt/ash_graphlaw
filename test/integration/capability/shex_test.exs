# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.ShexTest do
  @moduledoc "Typed `shex` against the REAL engine: both schema dialects (ShExC, ShExJ), per-node entries."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Shex, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control, both schema dialects" do
    test "ShExC (the default) validates and reports one entry per map association", %{opts: opts} do
      result = assert_typed_matches_raw("shex", args_of(example!("shex.shexc")), opts)
      assert %Result{conforms: conforms, entries: entries} = result
      assert is_boolean(conforms)
      assert length(entries) == 2
      assert Enum.all?(entries, &(is_map(&1) and not is_struct(&1)))
    end

    test "ShExJ with schema_dialect shexj validates the same shape", %{opts: opts} do
      shexc = assert_typed_matches_raw("shex", args_of(example!("shex.shexc")), opts)
      shexj_args = args_of(example!("shex.shexj"))
      assert shexj_args["schema_dialect"] == "shexj"
      shexj = assert_typed_matches_raw("shex", shexj_args, opts)
      assert shexj.conforms == shexc.conforms
      assert length(shexj.entries) == length(shexc.entries)
    end

    test "schema_dialect shexc given explicitly equals leaving it out", %{opts: opts} do
      args = args_of(example!("shex.shexc"))
      {:ok, default} = API.shex(args, opts)
      {:ok, explicit} = API.shex(Map.put(args, "schema_dialect", "shexc"), opts)
      assert default.raw == explicit.raw
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = args_of(example!("shex.shexc"))
      assert {:ok, %Result{} = api} = API.shex(args, opts)
      assert {:ok, ^api} = AshGraphLaw.shex(args, opts)
    end
  end

  describe "refusals" do
    test "a bad schema is an engine refusal", %{opts: opts} do
      assert_refusal(API.shex(args_of(example!("shex.bad-schema-refused")), opts), :engine_refused,
        kind: "EngineRejected"
      )
    end

    test "a ShExJ document handed over as ShExC is refused by the engine, not the client", %{opts: opts} do
      shexj_as_c = args_of(example!("shex.shexj")) |> Map.delete("schema_dialect")
      assert {:error, refusal} = API.shex(shexj_as_c, opts)
      assert refusal.code == :engine_refused
    end

    test "an unknown schema_dialect value is never enforced client-side", %{opts: opts} do
      args = args_of(example!("shex.shexc")) |> Map.put("schema_dialect", "shexz")
      assert {:ok, _request} = built("shex", args)
      assert {:error, refusal} = API.shex(args, opts)
      assert refusal.code == :engine_refused
    end

    test "missing map is refused client-side", %{opts: opts} do
      example = example!("shex.missing-map-refused")
      refusal = assert_refusal(API.shex(args_of(example), opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["map"]
    end
  end
end
