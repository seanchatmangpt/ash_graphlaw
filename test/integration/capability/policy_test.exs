# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.PolicyTest do
  @moduledoc "Typed `policy` against the REAL engine: json_or_string inputs, PolicyRefused mapping."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Policy, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "an admissible policy yields states and entries", %{opts: opts} do
      result = assert_typed_matches_raw("policy", args_of(example!("policy.accepted")), opts)

      assert %Result{initial_states: initial, reachable: reachable, goal_states: goals, entries: entries} = result
      assert initial == ["s0"]
      assert "g" in goals
      assert "s0" in reachable
      assert is_list(entries)
      assert is_binary(result.ntriples)
    end

    test "problem and policy given as JSON strings equal the object form", %{opts: opts} do
      args = args_of(example!("policy.accepted"))
      {:ok, objects} = API.policy(args, opts)

      strings = %{problem: Jason.encode!(args["problem"]), policy: Jason.encode!(args["policy"])}
      assert {:ok, %Result{} = from_strings} = API.policy(strings, opts)
      assert from_strings.reachable == objects.reachable
      assert from_strings.goal_states == objects.goal_states
      assert from_strings.entries == objects.entries
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = args_of(example!("policy.accepted"))
      assert {:ok, %Result{} = api} = API.policy(args, opts)
      assert {:ok, ^api} = AshGraphLaw.policy(args, opts)
    end

    test "every ok example is typed", %{opts: opts} do
      for {example, result} <- run_examples("policy", "ok", opts) do
        assert {:ok, %Result{}} = result, example["id"]
      end
    end
  end

  describe "refusals" do
    test "outcome mass not summing to one -> :policy_refused", %{opts: opts} do
      example = example!("policy.bad-mass-refused")
      refusal = assert_refusal(API.policy(args_of(example), opts), :policy_refused, wire_code: "PolicyRefused")
      assert is_binary(refusal.raw["kind"])
    end

    test "a dead end -> :policy_refused", %{opts: opts} do
      example = example!("policy.dead-end-refused")
      assert_refusal(API.policy(args_of(example), opts), :policy_refused, wire_code: "PolicyRefused")
    end

    test "missing policy is refused client-side", %{opts: opts} do
      example = example!("policy.missing-policy-refused")
      refusal = assert_refusal(API.policy(args_of(example), opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["policy"]
    end

    test "malformed JSON text is refused by the engine, not the client", %{opts: opts} do
      args = %{problem: "{not json", policy: "{}"}
      assert {:ok, _request} = built("policy", args)
      assert {:error, refusal} = API.policy(args, opts)
      assert refusal.code in [:engine_refused, :policy_refused]
    end
  end
end
