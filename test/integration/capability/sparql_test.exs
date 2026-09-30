# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.SparqlTest do
  @moduledoc "Typed `sparql` against the REAL engine: solutions, graph and boolean variants; term decoding."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.{Sparql, Term}

  @moduletag :wasm
  @moduletag :slow

  @data %{text: ~S(@prefix ex: <https://e/> . ex:s ex:p ex:o, "café"@fr, 42 ; a ex:T .), dialect: "turtle"}

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control: solutions" do
    test "SELECT gives kind :solutions with variables and typed term rows", %{opts: opts} do
      args = %{data: @data, query: "SELECT ?o WHERE { <https://e/s> <https://e/p> ?o } ORDER BY ?o"}
      result = assert_typed_matches_raw("sparql", args, opts)

      assert %Sparql{kind: :solutions, variables: ["o"], rows: rows} = result
      assert length(rows) == 3
      assert Enum.all?(rows, fn [term] -> match?(%Term{}, term) end)
      assert Enum.any?(rows, fn [term] -> term.lang == "fr" and term.value == "café" end)
      assert Enum.any?(rows, fn [term] -> term.value == "42" and is_binary(term.datatype) end)
    end

    test "Term keeps the engine object whole in :raw", %{opts: opts} do
      {:ok, %Sparql{rows: rows, raw: raw}} =
        API.sparql(%{data: @data, query: "SELECT ?o WHERE { <https://e/s> <https://e/p> ?o }"}, opts)

      raw_terms = Enum.flat_map(raw["rows"], & &1)
      typed_terms = Enum.flat_map(rows, & &1)
      assert Enum.map(typed_terms, & &1.raw) == raw_terms
    end
  end

  describe "positive control: graph and boolean" do
    test "CONSTRUCT gives kind :graph with N-Quads", %{opts: opts} do
      args = %{data: @data, query: "CONSTRUCT { ?s a <https://e/Thing> } WHERE { ?s a <https://e/T> }"}
      result = assert_typed_matches_raw("sparql", args, opts)
      assert %Sparql{kind: :graph, nquads: nquads, quads: quads} = result
      assert is_binary(nquads) and quads == 1
    end

    test "ASK gives kind :boolean, true and false", %{opts: opts} do
      yes = assert_typed_matches_raw("sparql", %{data: @data, query: "ASK { <https://e/s> a <https://e/T> }"}, opts)
      assert %Sparql{kind: :boolean, value: true} = yes

      assert {:ok, %Sparql{kind: :boolean, value: false}} =
               API.sparql(%{data: @data, query: "ASK { <https://e/s> a <https://e/Nope> }"}, opts)
    end

    test "the three example variants map to the three kinds", %{opts: opts} do
      kinds =
        for {example, result} <- run_examples("sparql", "ok", opts) do
          assert {:ok, %Sparql{kind: kind}} = result, example["id"]
          kind
        end

      assert Enum.sort(Enum.uniq(kinds)) == [:boolean, :graph, :solutions]
    end

    test "the root delegate returns the same typed struct", %{opts: opts} do
      args = %{data: @data, query: "ASK { ?s ?p ?o }"}
      assert {:ok, %Sparql{} = api} = API.sparql(args, opts)
      assert {:ok, ^api} = AshGraphLaw.sparql(args, opts)
    end
  end

  describe "refusals" do
    test "a syntax error is an engine refusal", %{opts: opts} do
      assert_refusal(API.sparql(args_of(example!("sparql.syntax-refused")), opts), :engine_refused,
        kind: "EngineRejected"
      )
    end

    test "missing query is a client refusal", %{opts: opts} do
      refusal = assert_refusal(API.sparql(%{data: @data}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["query"]
    end

    test "query of the wrong type is a client type error", %{opts: opts} do
      refusal = assert_refusal(API.sparql(%{data: @data, query: 7}, opts), :invalid_capability_request)
      assert [%{"field" => "query", "expected" => "string", "got" => got}] = refusal.details["type_errors"]
      assert is_binary(got)
    end
  end
end
