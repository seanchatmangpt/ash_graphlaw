# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written adversarial court over the typed capability ops.

defmodule AshGraphLaw.Adversarial.CapabilityOpsAdversarialTest do
  @moduledoc """
  Hostile input and hostile engines for the typed capability surface.

  Real engine (`:wasm`): a request over 16 MiB, JSON nested deeper than 64, plan/atom counts over
  their limits, and non-UTF-8 bytes are each refused with a TYPED refusal and leave the host usable.

  Real, spec-valid scripted wasm engine (`AshGraphLaw.Test.WasmFixtures.scripted_engine/1`, whose
  `gl_call` returns a fixed JSON body): forward compatibility. Unknown top-level keys, unknown
  variant tags, mistyped and missing fields survive in `:raw` and never raise; an unknown refusal
  kind or code becomes `:engine_unclassified` with `:raw` intact. The scripted engine ignores the
  request, so these tests establish how the library decodes response bytes, never what GraphLaw
  itself would answer.
  """
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.{Shacl, Sniff, Sparql, Term}
  alias AshGraphLaw.Test.WasmFixtures

  @mib 1_048_576

  defp nested(0), do: %{"leaf" => true}
  defp nested(n), do: %{"k" => nested(n - 1)}

  defp scripted(body) do
    start_host!(bytes: WasmFixtures.scripted_engine(call: {:json, Jason.encode!(body)}), expected_sha256: :unpinned)
  end

  describe "real engine: limits" do
    @describetag :wasm
    @describetag :slow

    setup do
      {:ok, opts: engine_opts!()}
    end

    test "positive control: a 1 MiB comment-padded document is parsed", %{opts: opts} do
      text = sample_turtle() <> "\n" <> String.duplicate("# padding padding padding\n", div(@mib, 26) + 1)
      assert byte_size(text) > @mib
      assert {:ok, %{quads: 4}} = API.parse(%{text: text, dialect: "turtle"}, opts)
    end

    test "a request over 16 MiB is a typed :resource_limit for every text-taking op", %{opts: opts} do
      big = String.duplicate("a", 16 * @mib + 1)

      cases = [
        {"parse", %{text: big, dialect: "turtle"}},
        {"canonical", %{data: %{text: big}}},
        {"sparql", %{data: %{text: sample_turtle()}, query: big}},
        {"shacl", %{data: %{text: sample_turtle()}, shapes: big}},
        {"n3", %{text: big}},
        {"sniff", %{text: big}}
      ]

      for {op, args} <- cases do
        refusal = assert_refusal(typed(op, args, opts), :resource_limit)
        assert refusal.class == :blocked_resource, op
        assert byte_size(inspect(refusal)) < 20_000, "#{op}: refusal echoes the payload"
      end

      assert {:ok, _} = API.sniff(%{text: sample_turtle()}, opts), "host unusable after refusals"
    end

    test "JSON nested deeper than 64 is :resource_limit naming json_depth; 20 deep is not", %{opts: opts} do
      deep = %{rules: [nested(100)], facts: []}
      refusal = assert_refusal(API.datalog(deep, opts), :resource_limit)
      assert refusal.details["limit"] == "json_depth"
      assert refusal.details["max"] == 64
      assert refusal.details["observed"] > 64

      shallow = %{rules: [nested(20)], facts: []}
      assert {:error, refusal} = API.datalog(shallow, opts)
      refute refusal.code == :resource_limit

      assert_refusal(API.law(%{data: %{text: sample_turtle()}, steps: [nested(100)]}, opts), :resource_limit)
    end

    test "more than 1000 plan actions is :resource_limit naming plan_actions", %{opts: opts} do
      actions = for i <- 1..1001, do: %{"name" => "a#{i}"}
      step = %{"step" => "plan", "plan" => %{"actions" => actions, "goal" => ""}}

      refusal =
        assert_refusal(API.law(%{data: %{text: "<urn:a> <urn:b> <urn:c> .\n"}, steps: [step]}, opts), :resource_limit)

      assert refusal.details["limit"] == "plan_actions"
      assert refusal.details["max"] == 1000
    end

    test "more than 10000 atoms in one plan field is :resource_limit naming atoms_per_field", %{opts: opts} do
      goal = Enum.map_join(1..10_001, "", fn i -> "<urn:s#{i}> <urn:p> <urn:o> .\n" end)
      step = %{"step" => "plan", "plan" => %{"actions" => [], "goal" => goal}}

      refusal =
        assert_refusal(API.law(%{data: %{text: "<urn:a> <urn:b> <urn:c> .\n"}, steps: [step]}, opts), :resource_limit)

      assert refusal.details["limit"] == "atoms_per_field"
    end
  end

  describe "real engine: non-UTF-8 bytes" do
    @describetag :wasm
    @describetag :slow

    setup do
      {:ok, opts: engine_opts!()}
    end

    test "invalid UTF-8 in any text-taking op is :invalid_encoding before the engine, at any depth", %{opts: opts} do
      bad = "ok" <> <<0xFF, 0xC0, 0x80>> <> "secret-marker"

      cases = [
        {"sniff", %{text: bad}},
        {"parse", %{text: bad, dialect: "turtle"}},
        {"convert", %{text: bad, dialect: "turtle", to: "turtle"}},
        {"canonical", %{data: %{text: bad}}},
        {"sparql", %{data: %{text: sample_turtle()}, query: bad}},
        {"shex", %{data: %{text: sample_turtle()}, schema: bad, map: "<urn:a>@<urn:b>"}},
        {"datalog", %{rules: [], facts: [["a", "b", bad]]}},
        {"law", %{data: %{text: sample_turtle()}, steps: [%{"step" => "shacl", "shapes" => bad}]}}
      ]

      for {op, args} <- cases do
        refusal = assert_refusal(typed(op, args, opts), :invalid_encoding)
        assert refusal.class == :refused_structure, op
        refute inspect(refusal) =~ "secret-marker", "#{op}: refusal echoes the bytes"
      end

      assert {:ok, _} = API.sniff(%{text: sample_turtle()}, opts)
    end

    test "valid multibyte text next to nothing invalid is not over-blocked", %{opts: opts} do
      text = ~S(@prefix ex: <https://e/> . ex:s ex:p "héllo ✓ 😀 日本語" .)
      assert {:ok, %{quads: 1}} = API.parse(%{text: text, dialect: "turtle"}, opts)
    end

    test "a control character and NUL inside text are answered or refused, never raised", %{opts: opts} do
      for text <- ["\0", "<urn:a> <urn:b> \"\u0001\" .", "\r\n\t\e"] do
        case API.sniff(%{text: text}, opts) do
          {:ok, %Sniff{}} -> :ok
          {:error, %Refusal{code: code}} -> assert code in Refusal.codes()
        end
      end
    end
  end

  describe "scripted engine: forward-compatible decoding" do
    test "positive control: a well-formed body decodes and raw is the whole map" do
      body = %{"ok" => true, "dialect" => "Turtle", "engine" => "PurRdf"}

      assert {:ok, %Sniff{dialect: "Turtle", engine: "PurRdf", raw: ^body}} =
               API.sniff(%{text: "x"}, server: scripted(body))
    end

    test "unknown top-level keys of every JSON shape survive in raw and do not disturb known fields" do
      extras = %{
        "future_string" => "x",
        "future_int" => 9_007_199_254_740_993,
        "future_float" => 1.5,
        "future_null" => nil,
        "future_bool" => false,
        "future_list" => [1, [2, %{"a" => nil}]],
        "future_map" => %{"nested" => %{"deeper" => ["✓", "日本語"]}},
        "" => "empty key"
      }

      body = Map.merge(%{"ok" => true, "conforms" => true, "results" => []}, extras)

      assert {:ok, %Shacl{conforms: true, results: [], raw: raw}} =
               API.shacl(%{data: "x", shapes: "y"}, server: scripted(body))

      assert raw == body
      assert Map.take(raw, Map.keys(extras)) == extras
    end

    test "a sparql body with an unknown kind is {:unknown, kind} and keeps every key" do
      body = %{"ok" => true, "kind" => "tensor", "rows" => [[1, 2]], "shape" => [2, 1]}

      assert {:ok, %Sparql{kind: {:unknown, "tensor"}, raw: ^body}} =
               API.sparql(%{data: "x", query: "q"}, server: scripted(body))
    end

    test "a sparql body with no kind, or a non-string kind, never raises" do
      for kind <- [nil, 7, ["solutions"], %{"a" => 1}] do
        body = %{"ok" => true, "kind" => kind, "variables" => ["o"], "rows" => []}
        assert {:ok, %Sparql{raw: ^body}} = API.sparql(%{data: "x", query: "q"}, server: scripted(body))
      end

      body = %{"ok" => true, "variables" => [], "rows" => []}
      assert {:ok, %Sparql{raw: ^body}} = API.sparql(%{data: "x", query: "q"}, server: scripted(body))
    end

    test "mistyped and missing fields never raise; the raw engine value is kept untouched" do
      mistyped = %{"ok" => true, "conforms" => "yes", "results" => 7}
      assert {:ok, %Shacl{raw: ^mistyped} = shacl} = API.shacl(%{data: "x", shapes: "y"}, server: scripted(mistyped))
      assert shacl.conforms == "yes"
      assert shacl.results == 7

      bare = %{"ok" => true}

      assert {:ok, %Shacl{conforms: nil, results: nil, raw: ^bare}} =
               API.shacl(%{data: "x", shapes: "y"}, server: scripted(bare))
    end

    test "term rows with unknown term keys and non-term cells keep the engine value in raw" do
      row = [
        %{"type" => "literal", "value" => "v", "xml:lang" => "fr", "surprise" => [1]},
        %{"type" => "uri", "value" => "https://e/x"},
        "not-a-term",
        42,
        nil
      ]

      body = %{"ok" => true, "kind" => "solutions", "variables" => ["a", "b", "c", "d", "e"], "rows" => [row]}

      assert {:ok, %Sparql{kind: :solutions, rows: [[first, second, third, fourth, fifth]], raw: ^body}} =
               API.sparql(%{data: "x", query: "q"}, server: scripted(body))

      assert %Term{type: "literal", value: "v", lang: "fr", raw: %{"surprise" => [1]}} = first
      assert %Term{type: "uri", value: "https://e/x"} = second
      assert {third, fourth, fifth} == {"not-a-term", 42, nil}
    end

    test "every typed op decodes an ok body with an injected unknown key losslessly" do
      for op <- op_names(), op != "law" do
        registry_fields = for f <- registry_op(op)["responses"] |> Enum.flat_map(& &1["fields"]), do: f["name"]

        body =
          Map.new(registry_fields, fn name -> {name, nil} end)
          |> Map.merge(%{"ok" => true, "injected_future_key" => %{"k" => [1]}})

        module = result_module(op)

        assert {:ok, %{__struct__: ^module, raw: raw}} =
                 typed(op, minimal_args(op), server: scripted(body)),
               op

        assert raw == body, op
      end
    end
  end

  describe "scripted engine: unknown refusals" do
    test "positive control: a known kind is :engine_refused with kind and raw kept" do
      error = %{"kind" => "EngineRejected", "message" => "m", "engine" => "PurRdf", "dialect" => "Turtle"}
      body = %{"ok" => false, "error" => error}
      refusal = assert_refusal(API.sniff(%{text: "x"}, server: scripted(body)), :engine_refused, kind: "EngineRejected")
      assert refusal.raw == error
    end

    test "an unknown refusal kind is :engine_unclassified (class unsupported) with raw intact" do
      error = %{"kind" => "QuantumFoam", "message" => "new", "details" => %{"future" => [1]}, "novel" => %{"x" => nil}}
      body = %{"ok" => false, "error" => error}

      for op_args <- [{"sniff", %{text: "x"}}, {"sparql", %{data: "x", query: "q"}}, {"law", %{data: "x", steps: []}}] do
        {op, args} = op_args
        refusal = assert_refusal(typed(op, args, server: scripted(body)), :engine_unclassified)
        assert refusal.class == :unsupported
        assert refusal.raw == error, op
        assert refusal.kind == "QuantumFoam"
      end
    end

    test "a non-string details.code is :engine_unclassified with raw intact" do
      for code <- [7, ["NotAdmitted"], %{"a" => 1}] do
        error = %{"kind" => "EngineRejected", "details" => %{"code" => code}}
        body = %{"ok" => false, "error" => error}
        refusal = assert_refusal(API.law(%{data: "x", steps: []}, server: scripted(body)), :engine_unclassified)
        assert refusal.raw == error
      end
    end

    test "an unknown string details.code under a known kind falls back to the kind, raw intact" do
      error = %{"kind" => "EngineRejected", "details" => %{"code" => "FutureRefusal", "why" => "new"}}
      body = %{"ok" => false, "error" => error}

      refusal =
        assert_refusal(API.law(%{data: "x", steps: []}, server: scripted(body)), :engine_refused,
          kind: "EngineRejected"
        )

      assert refusal.raw == error
    end

    test "an unknown string details.code under an unknown kind is :engine_unclassified" do
      error = %{"kind" => "Nope", "details" => %{"code" => "FutureRefusal"}}
      body = %{"ok" => false, "error" => error}

      assert %{raw: ^error} =
               assert_refusal(API.law(%{data: "x", steps: []}, server: scripted(body)), :engine_unclassified)
    end

    test "an error that is not even a map, and a body with no ok, are typed refusals" do
      assert {:error, %Refusal{code: :malformed_response}} =
               API.sniff(%{text: "x"}, server: scripted(%{"ok" => false, "error" => "boom"}))

      assert {:error, %Refusal{code: :malformed_response}} =
               API.sniff(%{text: "x"}, server: scripted(%{"dialect" => "Turtle"}))

      assert {:error, %Refusal{code: :malformed_response}} = API.sniff(%{text: "x"}, server: scripted([1, 2]))
    end
  end

  # Smallest args that pass client validation for `op`.
  defp minimal_args(op) do
    for f <- registry_op(op)["request"]["fields"], f["required"], into: %{} do
      {f["name"], minimal_value(f["type"])}
    end
  end

  defp minimal_value("string"), do: "x"
  defp minimal_value("data_spec"), do: "x"
  defp minimal_value("json_or_string"), do: "{}"
  defp minimal_value("integer"), do: 1
  defp minimal_value("boolean"), do: true
  defp minimal_value("object"), do: %{}
  defp minimal_value("list" <> _), do: []
  defp minimal_value(_), do: %{}
end
