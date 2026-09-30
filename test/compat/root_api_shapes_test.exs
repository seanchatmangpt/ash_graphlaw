# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Compat.RootApiShapesTest do
  @moduledoc """
  Back-compat court for the root API: `call/2`, `capabilities/1`, `sniff/3`, `law/3`, `hooks/3`,
  `engine_sha256/1`, `abi_version/0` and `graphlaw_release/0` keep their exact names, arities and
  return shapes while the typed capability surface lands beside them.

  The shapes below are LITERAL expectations snapshotted from `lib/ash_graphlaw.ex` and
  `test/unit/root_api_test.exs` before the capability lanes landed. Tests tagged `:wasm` run
  against the REAL vendored engine; the untagged tests drive a real host over a spec-valid
  scripted WebAssembly module (no mocks) to pin how response bytes become typed values.

  UNSUPPORTED(generator-capability): hand-written Chicago test.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.{Admitted, Receipt}
  alias AshGraphLaw.Test.WasmFixtures

  # ABI 1 ops in ABI order. Engines older than v26.9.29 serve the first 13 (no `policy`, no
  # `abi_version` key in capabilities); v26.9.29+ serves all 14. Tests below accept exactly those two
  # shapes, so the suite is green before and after the engine pin bump and drift in either is caught.
  @legacy_ops ~w(capabilities sniff parse convert canonical sparql shacl shex n3 entail datalog hooks law)
  @rdf_dialects ~w(turtle trig ntriples nquads rdfxml jsonld yamlld trix hextuples)
  @other_dialects ~w(n3 sparql shexc shexj)

  @exports [
    {:call, 1},
    {:call, 2},
    {:capabilities, 0},
    {:capabilities, 1},
    {:sniff, 1},
    {:sniff, 2},
    {:sniff, 3},
    {:law, 2},
    {:law, 3},
    {:hooks, 2},
    {:hooks, 3},
    {:engine_sha256, 0},
    {:engine_sha256, 1},
    {:abi_version, 0},
    {:graphlaw_release, 0}
  ]

  @turtle "@prefix ex: <https://e/> . ex:s ex:p ex:o ."
  @good_nt "<https://e/a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/T> .\n<https://e/a> <https://e/name> \"a\" .\n"
  @bad_nt "<https://e/a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/T> .\n"
  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> . @prefix ex: <https://e/> .
  ex:S a sh:NodeShape ; sh:targetClass ex:T ;
    sh:property [ sh:path ex:name ; sh:minCount 1 ] .
  """

  defp scripted(body) do
    start_host!(bytes: WasmFixtures.scripted_engine(call: {:json, Jason.encode!(body)}), expected_sha256: :unpinned)
  end

  describe "public function surface (no engine needed)" do
    test "positive control: the module is loaded and exports its identity functions" do
      assert {:module, AshGraphLaw} = Code.ensure_loaded(AshGraphLaw)
      assert function_exported?(AshGraphLaw, :abi_version, 0)
    end

    test "every legacy root function keeps its name and arity" do
      for {name, arity} <- @exports do
        assert function_exported?(AshGraphLaw, name, arity), "AshGraphLaw.#{name}/#{arity} disappeared"
      end
    end

    test "abi_version/0 is the integer 1 and graphlaw_release/0 is a CalVer string equal to the manifest pin" do
      assert AshGraphLaw.abi_version() === 1
      release = AshGraphLaw.graphlaw_release()
      assert is_binary(release)
      assert release =~ ~r/\A\d+\.\d+\.\d+\z/
      assert release == manifest()["graphlaw_version"]
    end

    test "call/2 rejects a non-map request with a FunctionClauseError, never a refusal" do
      assert_raise FunctionClauseError, fn -> AshGraphLaw.call([op: "capabilities"], []) end
      assert_raise FunctionClauseError, fn -> AshGraphLaw.call(%{"op" => "capabilities"}, :server) end
    end

    test "sniff/3 rejects non-binary text and law/3 rejects a non-list steps argument" do
      assert_raise FunctionClauseError, fn -> AshGraphLaw.sniff(:not_text, nil, []) end
      assert_raise FunctionClauseError, fn -> AshGraphLaw.law("x", %{"step" => "shacl"}, []) end
    end
  end

  describe "return shapes over a real host running a scripted engine" do
    test "positive control: call/2 returns {:ok, response} carrying the \"ok\" key untouched" do
      body = %{"ok" => true, "answer" => 42, "nested" => %{"k" => [1, 2, 3]}}
      assert {:ok, ^body} = AshGraphLaw.call(%{"op" => "capabilities"}, server: scripted(body))
    end

    test "capabilities/1, sniff/3 and hooks/3 return the engine map verbatim (string keys, no struct)" do
      body = %{"ok" => true, "extra_key_from_a_newer_engine" => "kept"}
      s = scripted(body)

      assert {:ok, ^body} = AshGraphLaw.capabilities(server: s)
      assert {:ok, ^body} = AshGraphLaw.sniff("<a> <b> <c> .", "nt", server: s)
      assert {:ok, ^body} = AshGraphLaw.sniff("<a> <b> <c> .", nil, server: s)
      assert {:ok, ^body} = AshGraphLaw.hooks("data", %{"text" => "pack"}, server: s)
      assert {:ok, ^body} = AshGraphLaw.hooks(%{"text" => "data"}, "pack", server: s)
    end

    test "law/3 wraps an admitted body in %Admitted{} with %Receipt{} rows and keeps the raw map" do
      body = %{
        "ok" => true,
        "states" => ["s0", "s1"],
        "receipts" => [%{"step" => "admit:shacl", "parent" => "s0", "child" => "s1", "authority" => "purrdf::shapes"}],
        "nquads" => "<urn:a:x> <urn:a:p> <urn:a:y> <urn:g> .\n"
      }

      assert {:ok, %Admitted{states: ["s0", "s1"], receipts: [%Receipt{} = r], nquads: nquads, raw: raw}} =
               AshGraphLaw.law("<urn:a:x> <urn:a:p> <urn:a:y> .", [%{"step" => "shacl"}], server: scripted(body))

      assert r.step == "admit:shacl"
      assert r.parent == "s0"
      assert r.child == "s1"
      assert r.authority == "purrdf::shapes"
      assert nquads == body["nquads"]
      assert raw == body
    end

    test "a refusal body stays {:error, %Refusal{}} through call/2 and law/3 alike" do
      body = %{
        "ok" => false,
        "error" => %{"kind" => "Refused", "message" => "no"},
        "details" => %{"code" => "NotAdmitted"}
      }

      s = scripted(body)

      assert {:error, %Refusal{code: :not_admitted, class: :refused_admission}} =
               AshGraphLaw.call(%{"op" => "law"}, server: s)

      assert {:error, %Refusal{code: :not_admitted}} = AshGraphLaw.law(%{"text" => "x"}, [], server: s)
    end

    test "engine_sha256/1 names the bytes behind the server and is nil for an unknown server" do
      bytes = WasmFixtures.scripted_engine(call: {:json, ~s({"ok":true})})
      host = start_host!(bytes: bytes, expected_sha256: :unpinned)

      assert AshGraphLaw.engine_sha256(server: host) == WasmFixtures.sha256(bytes)
      assert AshGraphLaw.engine_sha256(server: :agl_compat_no_such_host) == nil
    end
  end

  describe "return shapes against the real engine" do
    @describetag :wasm

    setup do
      %{server: start_host!([])}
    end

    test "capabilities/1: {:ok, map} with the legacy keys, exact op order and dialect lists", %{server: s} do
      assert {:ok, %{} = caps} = AshGraphLaw.capabilities(server: s)

      assert caps["ok"] == true
      assert caps["abi"] == 1
      assert Map.get(caps, "abi_version", 1) == 1
      assert is_binary(caps["crate"])
      assert Enum.take(caps["ops"], 13) == @legacy_ops
      assert (caps["ops"] -- @legacy_ops) in [[], ["policy"]]
      assert caps["rdf_dialects"] == @rdf_dialects
      assert caps["other_dialects"] == @other_dialects

      assert [_ | _] = authorities = caps["authorities"]
      assert Enum.all?(authorities, &(is_binary(&1["capability"]) and is_binary(&1["authority"])))

      # additive keys are allowed (registry_schema, registry_sha256, surface_sha256); nothing legacy may vanish
      legacy = ~w(ok abi crate authorities rdf_dialects other_dialects ops)
      assert legacy -- Map.keys(caps) == []
    end

    test "capabilities/1 lists 13 ops on a pre-v26.9.29 engine and 14 from v26.9.29", %{server: s} do
      assert {:ok, %{"ops" => ops}} = AshGraphLaw.capabilities(server: s)
      assert length(ops) in [13, 14]
    end

    test "sniff/3: {:ok, %{\"dialect\", \"engine\"}} with and without a hint; garbage is a typed refusal", %{server: s} do
      assert {:ok, %{"ok" => true, "dialect" => dialect, "engine" => engine}} =
               AshGraphLaw.sniff(@turtle, nil, server: s)

      assert is_binary(dialect)
      assert engine in ["PurRdf", "Eyeron"]

      assert {:ok, %{"dialect" => ^dialect}} = AshGraphLaw.sniff(@turtle, "ttl", server: s)

      assert {:error, %Refusal{} = refusal} = AshGraphLaw.sniff("<!DOCTYPE html><html></html>", nil, server: s)
      assert is_atom(refusal.code)
      assert is_atom(refusal.class)
      assert is_binary(refusal.message)
    end

    test "law/3: admitted data is %Admitted{} with one %Receipt{} and unchanged states; PARTIAL_ALIVE at most", %{
      server: s
    } do
      result =
        AshGraphLaw.law(%{"text" => @good_nt, "dialect" => "ntriples"}, [%{"step" => "shacl", "shapes" => @shapes}],
          server: s
        )

      assert {:ok,
              %Admitted{states: [same, same], receipts: [%Receipt{} = receipt], nquads: nquads, raw: %{"ok" => true}}} =
               result

      assert receipt.step == "admit:shacl"
      assert receipt.authority == "purrdf::shapes"
      assert is_binary(nquads)
      assert AshGraphLaw.Standing.of(result) == :PARTIAL_ALIVE
    end

    test "law/3: bare text is accepted as data and violating data is :not_admitted with violations", %{server: s} do
      steps = [%{"step" => "shacl", "shapes" => @shapes}]
      assert {:ok, %Admitted{}} = AshGraphLaw.law(@good_nt, steps, server: s)

      assert {:error, %Refusal{} = refusal} =
               AshGraphLaw.law(%{"text" => @bad_nt, "dialect" => "ntriples"}, steps, server: s)

      # v26.9.29+ engines tag the refusal details.code "NotAdmitted"; earlier engines return the bare
      # EngineRejected kind with the same message and no details.code.
      assert refusal.code in [:not_admitted, :engine_refused]
      assert refusal.message =~ "SHACL admission refused"
      assert refusal.broken_term == :mu_on_O
      assert is_map(refusal.details)
    end

    test "law/3 accepts the authority opts (lease, unverified_lease, now_unix) and still returns %Admitted{}", %{
      server: s
    } do
      steps = [%{"step" => "rdfs"}]
      data = %{"text" => @good_nt, "dialect" => "ntriples"}

      # positive control: without authority opts the step is admitted
      assert {:ok, %Admitted{states: [_, _], receipts: [%Receipt{step: "derive:rdfs"}]}} =
               AshGraphLaw.law(data, steps, server: s)

      lease = %{
        "id" => "L-compat",
        "holder" => "t",
        "ceiling" => "construct",
        "scope" => ["derive:rdfs"],
        "expires_unix" => 100,
        "issued_unix" => 0
      }

      assert {:ok, %Admitted{states: [_, _], receipts: [%Receipt{step: "derive:rdfs"}]}} =
               AshGraphLaw.law(data, steps, server: s, lease: lease, unverified_lease: true, now_unix: 50)
    end

    test "hooks/3: {:ok, map} with id, rounds, quads, nquads and firings; text or data spec both accepted", %{server: s} do
      data = "<https://e/x> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/A> .\n"

      assert {:ok, %{"ok" => true} = resp} =
               AshGraphLaw.hooks(
                 %{"text" => data, "dialect" => "ntriples"},
                 %{"text" => chain_pack(), "dialect" => "turtle"},
                 server: s
               )

      assert is_binary(resp["id"])
      assert is_integer(resp["rounds"])
      assert is_integer(resp["quads"])
      assert is_binary(resp["nquads"])
      assert [_ | _] = resp["firings"]
      assert resp["nquads"] =~ "https://e/B"

      assert {:ok, %{"id" => id}} = AshGraphLaw.hooks(data, chain_pack(), server: s)
      assert id == resp["id"]
    end

    test "call/2: a request map with string keys goes through unchanged; unknown ops are typed refusals", %{server: s} do
      assert {:ok, %{"ok" => true, "abi" => 1}} = AshGraphLaw.call(%{"op" => "capabilities"}, server: s)

      assert {:error, %Refusal{} = refusal} = AshGraphLaw.call(%{"op" => "nope"}, server: s)
      assert is_atom(refusal.code)
      assert refusal.message =~ "unknown op"
    end

    test "engine_sha256/1 is the manifest pin for the vendored engine; abi_version/0 matches the live abi", %{server: s} do
      assert AshGraphLaw.engine_sha256(server: s) == manifest_pin()
      assert {:ok, %{"abi" => live}} = AshGraphLaw.capabilities(server: s)
      assert live == AshGraphLaw.abi_version()
    end
  end

  # Two chained sparql-construct hooks (A -> B, then B -> C); pack shape from graphlaw tests/knowledge_hooks.rs.
  defp chain_pack do
    kh = "http://seanchatmangpt.github.io/praxis/kh#"
    handler = "http://seanchatmangpt.github.io/praxis/handler#sparql-construct"

    mk = fn n, from, to, prio ->
      """
      ex:h#{n} a kh:Hook ; kh:kind "sparql" ; kh:effect "emit-delta" ; kh:priority #{prio} ; kh:action ex:a#{n} ;
        kh:query "SELECT ?x WHERE { ?x a <https://e/#{from}> }" .
      ex:a#{n} a kh:Action ; kh:handler <#{handler}> ;
        kh:query "CONSTRUCT { ?x a <https://e/#{to}> } WHERE { ?x a <https://e/#{from}> }" .
      """
    end

    "@prefix kh: <#{kh}> . @prefix ex: <https://e/> .\n" <> mk.(1, "A", "B", 1) <> mk.(2, "B", "C", 2)
  end
end
