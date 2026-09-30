# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Compat.RawCallOpsTest do
  @moduledoc """
  Raw `AshGraphLaw.call/2` keeps working for each of the 14 GraphLaw ABI 1 operations against the
  REAL vendored engine, whether or not the typed capability modules exist. Each request is
  self-contained inline text; each expectation is a literal response key set or value taken from
  graphlaw `tests/wasm_abi.rs`. This is the floor the typed surface must never remove.

  UNSUPPORTED(generator-capability): hand-written Chicago test.
  """

  use AshGraphLaw.Test.Case, async: false

  @moduletag :wasm

  @ops ~w(capabilities sniff parse convert canonical sparql shacl shex n3 entail datalog hooks law policy)

  # Engines older than v26.9.29 serve only the first 13 ops (no `policy`, no capabilities `abi_version`).
  # Such an engine must refuse `policy` as an unknown op; v26.9.29+ must serve it. Nothing else may differ.
  @legacy_ops List.delete(@ops, "policy")

  @turtle "@prefix ex: <https://e/> . ex:s ex:p ex:o, 42 ; a ex:T ."
  @nt "<https://e/s> <https://e/p> <https://e/o> .\n<https://e/s> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/T> .\n"
  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> . @prefix ex: <https://e/> . @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  ex:S a sh:NodeShape ; sh:targetClass ex:T ; sh:property [ sh:path ex:p ; sh:datatype xsd:integer ] .
  """
  @kh "http://seanchatmangpt.github.io/praxis/kh#"
  @handler "http://seanchatmangpt.github.io/praxis/handler#sparql-construct"

  @requests %{
    "capabilities" => %{"op" => "capabilities"},
    "sniff" => %{"op" => "sniff", "text" => @turtle},
    "parse" => %{"op" => "parse", "text" => @turtle, "dialect" => "turtle"},
    "convert" => %{"op" => "convert", "text" => @turtle, "dialect" => "turtle", "to" => "ntriples"},
    "canonical" => %{"op" => "canonical", "data" => %{"text" => @nt, "dialect" => "ntriples"}},
    "sparql" => %{
      "op" => "sparql",
      "data" => %{"text" => @nt, "dialect" => "ntriples"},
      "query" => "SELECT ?o WHERE { <https://e/s> <https://e/p> ?o } ORDER BY ?o"
    },
    "shacl" => %{"op" => "shacl", "data" => %{"text" => @turtle, "dialect" => "turtle"}, "shapes" => @shapes},
    "shex" => %{
      "op" => "shex",
      "data" => %{"text" => "@prefix ex: <https://e/> . ex:cat ex:says \"meow\" ."},
      "schema" => "PREFIX ex: <https://e/>\nex:Cat { ex:says . }",
      "map" => "<https://e/cat>@<https://e/Cat>"
    },
    "n3" => %{
      "op" => "n3",
      "text" => "@prefix : <https://e/> . :s a :Human . { ?x a :Human } => { ?x a :Mortal } ."
    },
    "entail" => %{
      "op" => "entail",
      "data" => %{
        "text" =>
          "@prefix ex: <https://e/> . @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> . ex:Cat rdfs:subClassOf ex:Animal . ex:tom a ex:Cat ."
      },
      "regime" => "rdfs"
    },
    "datalog" => %{
      "op" => "datalog",
      "rules" => [
        %{"head" => ["?x", "https://e/anc", "?y"], "body" => [["?x", "https://e/par", "?y"]]},
        %{
          "head" => ["?x", "https://e/anc", "?z"],
          "body" => [["?x", "https://e/anc", "?y"], ["?y", "https://e/par", "?z"]]
        }
      ],
      "facts" => [["https://e/a", "https://e/par", "https://e/b"], ["https://e/b", "https://e/par", "https://e/c"]]
    },
    "hooks" => %{
      "op" => "hooks",
      "pack" => %{
        "text" =>
          "@prefix kh: <#{@kh}> . @prefix ex: <https://e/> .\n" <>
            "ex:h1 a kh:Hook ; kh:kind \"sparql\" ; kh:effect \"emit-delta\" ; kh:priority 1 ; kh:action ex:a1 ;\n" <>
            "  kh:query \"SELECT ?x WHERE { ?x a <https://e/A> }\" .\n" <>
            "ex:a1 a kh:Action ; kh:handler <#{@handler}> ;\n" <>
            "  kh:query \"CONSTRUCT { ?x a <https://e/B> } WHERE { ?x a <https://e/A> }\" .\n",
        "dialect" => "turtle"
      },
      "data" => %{
        "text" => "<https://e/x> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/A> .\n",
        "dialect" => "ntriples"
      }
    },
    "law" => %{
      "op" => "law",
      "data" => %{"text" => @nt, "dialect" => "ntriples"},
      "steps" => [
        %{
          "step" => "shacl",
          "shapes" =>
            "@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix ex: <https://e/> . ex:S a sh:NodeShape ; sh:targetClass ex:T ; sh:property [ sh:path ex:p ; sh:minCount 1 ] ."
        }
      ]
    },
    "policy" => %{
      "op" => "policy",
      "problem" => %{
        "states" => [%{"id" => "s0"}, %{"id" => "g", "facts" => ["done"]}],
        "initial_states" => ["s0"],
        "goal" => %{"facts" => ["done"]},
        "transitions" => [
          %{"action" => "flip", "from" => "s0", "to" => "g", "probability_ppm" => 500_000},
          %{"action" => "flip", "from" => "s0", "to" => "s0", "probability_ppm" => 500_000}
        ]
      },
      "policy" => %{
        "policy" => [
          %{
            "state" => "s0",
            "action" => "flip",
            "outcomes" => [
              %{"state" => "g", "probability_ppm" => 500_000},
              %{"state" => "s0", "probability_ppm" => 500_000}
            ]
          }
        ]
      }
    }
  }

  # Literal response keys each op must keep emitting (additive keys are allowed, removal is drift).
  @response_keys %{
    "capabilities" => ~w(ok abi crate authorities rdf_dialects other_dialects ops),
    "sniff" => ~w(ok dialect engine),
    "parse" => ~w(ok dialect quads id),
    "convert" => ~w(ok text id),
    "canonical" => ~w(ok id nquads quads),
    "sparql" => ~w(ok kind variables rows),
    "shacl" => ~w(ok conforms results),
    "shex" => ~w(ok conforms entries),
    "n3" => ~w(ok derived),
    "entail" => ~w(ok nquads added),
    "datalog" => ~w(ok count facts),
    "hooks" => ~w(ok id rounds quads nquads firings),
    "law" => ~w(ok states receipts nquads),
    "policy" => ~w(ok initial_states reachable goal_states entries ntriples)
  }

  setup do
    %{server: start_host!([])}
  end

  defp served?(server, op) do
    {:ok, %{"ops" => ops}} = AshGraphLaw.capabilities(server: server)
    op in ops
  end

  test "the request table covers exactly the 14 ABI ops in ABI order" do
    assert Map.keys(@requests) |> Enum.sort() == Enum.sort(@ops)
    assert Map.keys(@response_keys) |> Enum.sort() == Enum.sort(@ops)
    assert length(@ops) == 14
  end

  test "positive control: capabilities through call/2 reports the 13 legacy ops, plus policy from v26.9.29", %{
    server: s
  } do
    assert {:ok, %{"ops" => ops}} = AshGraphLaw.call(@requests["capabilities"], server: s)
    assert Enum.take(ops, 13) == @legacy_ops
    assert (ops -- @legacy_ops) in [[], ["policy"]]
  end

  for op <- @ops do
    test "raw call/2 op #{op}: {:ok, map} with the legacy response keys", %{server: s} do
      op = unquote(op)

      if op == "policy" and not served?(s, "policy") do
        assert {:error, %Refusal{message: message}} = AshGraphLaw.call(Map.fetch!(@requests, op), server: s)
        assert message =~ "unknown op `policy`"
      else
        assert {:ok, %{"ok" => true} = resp} = AshGraphLaw.call(Map.fetch!(@requests, op), server: s)

        missing = Map.fetch!(@response_keys, op) -- Map.keys(resp)
        assert missing == [], "op #{op} lost response keys #{inspect(missing)}: #{inspect(resp, limit: 8)}"
      end
    end
  end

  describe "literal response values" do
    test "parse/convert/canonical agree on the graph identity of the same document", %{server: s} do
      assert {:ok, %{"dialect" => "Turtle", "quads" => 3, "id" => id}} = AshGraphLaw.call(@requests["parse"], server: s)
      assert is_binary(id)

      assert {:ok, %{"text" => text, "id" => ^id}} = AshGraphLaw.call(@requests["convert"], server: s)
      assert text =~ "<https://e/s> <https://e/p> <https://e/o>"

      assert {:ok, %{"quads" => 2, "nquads" => nquads}} = AshGraphLaw.call(@requests["canonical"], server: s)
      assert is_binary(nquads)
    end

    test "sparql SELECT is tagged solutions and ASK is tagged boolean", %{server: s} do
      assert {:ok, %{"kind" => "solutions", "variables" => ["o"], "rows" => [[_ | _]]}} =
               AshGraphLaw.call(@requests["sparql"], server: s)

      ask = %{@requests["sparql"] | "query" => "ASK { <https://e/s> a <https://e/T> }"}
      assert {:ok, %{"kind" => "boolean", "value" => true}} = AshGraphLaw.call(ask, server: s)
    end

    test "shacl reports non-conformance with results; n3 derives Mortal; datalog reaches a fixpoint", %{server: s} do
      assert {:ok, %{"conforms" => false, "results" => [_ | _]}} = AshGraphLaw.call(@requests["shacl"], server: s)
      assert {:ok, %{"derived" => derived}} = AshGraphLaw.call(@requests["n3"], server: s)
      assert derived =~ "Mortal"
      assert {:ok, %{"count" => 5, "facts" => facts}} = AshGraphLaw.call(@requests["datalog"], server: s)
      assert ["https://e/a", "https://e/anc", "https://e/c"] in facts
    end

    test "entail rdfs adds the inferred type; hooks fire once; policy names the goal state", %{server: s} do
      assert {:ok, %{"nquads" => nquads, "added" => added}} = AshGraphLaw.call(@requests["entail"], server: s)
      assert added > 0
      assert nquads =~ "<https://e/tom> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/Animal>"

      assert {:ok, %{"firings" => [_], "nquads" => hooked}} = AshGraphLaw.call(@requests["hooks"], server: s)
      assert hooked =~ "https://e/B"

      if served?(s, "policy") do
        assert {:ok, %{"goal_states" => ["g"], "entries" => [["s0", "flip"]]}} =
                 AshGraphLaw.call(@requests["policy"], server: s)
      end
    end

    test "law admits with a receipt whose authority is the engine's SHACL backend", %{server: s} do
      assert {:ok, %{"states" => [_, _], "receipts" => [%{"authority" => "purrdf::shapes"}]}} =
               AshGraphLaw.call(@requests["law"], server: s)
    end
  end

  describe "refusals stay typed through raw call/2" do
    test "every op refuses a request missing its required field as {:error, %Refusal{}}", %{server: s} do
      # positive control first: the full request succeeds
      assert {:ok, _} = AshGraphLaw.call(@requests["sniff"], server: s)

      for op <- @ops -- ["capabilities"] do
        bare = %{"op" => op}

        assert {:error, %Refusal{code: code, class: class, message: message}} = AshGraphLaw.call(bare, server: s),
               "op #{op} accepted an empty request"

        assert is_atom(code) and is_atom(class) and is_binary(message)
      end
    end

    test "an unknown op is refused and named", %{server: s} do
      assert {:error, %Refusal{message: message}} = AshGraphLaw.call(%{"op" => "compat_no_such_op"}, server: s)
      assert message =~ "unknown op"
    end
  end
end
