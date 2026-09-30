# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.DatalogTest do
  @moduledoc "Typed `datalog` against the REAL engine: fixpoint facts, empty rules, malformed atoms."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Datalog, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "ancestor closure derives the transitive fact", %{opts: opts} do
      result = assert_typed_matches_raw("datalog", args_of(example!("datalog.ancestor")), opts)
      assert %Result{count: count, facts: facts} = result
      assert is_integer(count)
      assert ["https://e/a", "https://e/anc", "https://e/c"] in facts
      assert facts == result.raw["facts"]
    end

    test "no rules keeps only the given facts", %{opts: opts} do
      example = example!("datalog.no-rules")
      assert {:ok, %Result{facts: facts}} = API.datalog(args_of(example), opts)
      assert Enum.sort(facts) == Enum.sort(example["request"]["facts"])
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = args_of(example!("datalog.ancestor"))
      assert {:ok, %Result{} = api} = API.datalog(args, opts)
      assert {:ok, ^api} = AshGraphLaw.datalog(args, opts)
    end
  end

  describe "refusals" do
    test "a malformed atom is an engine refusal", %{opts: opts} do
      assert_refusal(API.datalog(args_of(example!("datalog.bad-atom-refused")), opts), :engine_refused,
        kind: "Unsupported"
      )
    end

    test "missing facts is refused client-side", %{opts: opts} do
      refusal = assert_refusal(API.datalog(%{rules: []}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["facts"]
    end

    test "facts of the wrong type are a client type error", %{opts: opts} do
      refusal = assert_refusal(API.datalog(%{rules: [], facts: "nope"}, opts), :invalid_capability_request)
      assert [%{"field" => "facts", "expected" => "list<list<string>>"}] = refusal.details["type_errors"]
    end
  end
end
