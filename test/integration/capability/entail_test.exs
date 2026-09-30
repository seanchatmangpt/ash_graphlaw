# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.EntailTest do
  @moduledoc "Typed `entail` against the REAL engine: all five regimes."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Capability.Registry
  alias AshGraphLaw.Result.Entail, as: Result

  @moduletag :wasm
  @moduletag :slow

  @data %{
    text:
      "@prefix ex: <https://e/> . @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> . " <>
        "ex:Cat rdfs:subClassOf ex:Animal . ex:tom a ex:Cat ."
  }

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "rdfs entailment adds triples and reports the count", %{opts: opts} do
      result = assert_typed_matches_raw("entail", %{data: @data, regime: "rdfs"}, opts)
      assert %Result{added: added, nquads: nquads} = result
      assert is_integer(added) and added > 0
      assert nquads =~ "https://e/Animal"
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = %{data: @data, regime: "rdfs"}
      assert {:ok, %Result{} = api} = API.entail(args, opts)
      assert {:ok, ^api} = AshGraphLaw.entail(args, opts)
    end
  end

  describe "all five regimes" do
    test "the registry regimes are simple rdf rdfs owl-rl d" do
      assert Registry.regimes() == ~w(simple rdf rdfs owl-rl d)
    end

    test "every regime is accepted and typed, and richer regimes never add fewer than simple", %{opts: opts} do
      added =
        for regime <- Registry.regimes(), into: %{} do
          assert {:ok, %Result{added: added, raw: %{"ok" => true}}} =
                   API.entail(%{data: @data, regime: regime}, opts),
                 "regime #{regime}"

          assert is_integer(added)
          {regime, added}
        end

      assert added["rdfs"] >= added["simple"]
      assert added["owl-rl"] >= added["simple"]
    end

    test "each example regime has an ok example", %{opts: opts} do
      for {example, result} <- run_examples("entail", "ok", opts) do
        assert {:ok, %Result{}} = result, example["id"]
      end

      regimes = for e <- examples_for("entail"), e["outcome"] == "ok", do: e["request"]["regime"]
      assert Enum.sort(regimes) == Enum.sort(Registry.regimes())
    end
  end

  describe "refusals" do
    test "an unknown regime is refused by the engine (enum is informational client-side)", %{opts: opts} do
      example = example!("entail.unknown-regime-refused")
      assert {:ok, _request} = built("entail", args_of(example))
      assert_refusal(API.entail(args_of(example), opts), :engine_refused, kind: "Unsupported")
    end

    test "missing regime is refused client-side", %{opts: opts} do
      refusal = assert_refusal(API.entail(%{data: @data}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["regime"]
    end

    test "unparsable data is an engine refusal", %{opts: opts} do
      assert_refusal(API.entail(%{data: %{text: "%%%", dialect: "turtle"}, regime: "rdfs"}, opts), :engine_refused,
        kind: "EngineRejected"
      )
    end
  end
end
