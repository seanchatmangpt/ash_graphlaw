# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Unit.CapabilityCoerceTest.Fields do
  @moduledoc false
  # UNSUPPORTED(generator-capability): field-map builder for the coercion suite.
  def field(name, type, opts \\ []) do
    %{
      name: name,
      order: Keyword.get(opts, :order, 1),
      type: type,
      required: Keyword.get(opts, :required, false),
      nullable: false,
      doc: "",
      enum: Keyword.get(opts, :enum),
      default: nil
    }
  end
end

defmodule AshGraphLaw.Unit.CapabilityCoerceTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago suite for the argument coercion helper.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Capability.Coerce
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Unit.CapabilityCoerceTest.Fields

  import Fields, only: [field: 3]

  @fields [
    field("data", "data_spec", required: true, order: 1),
    field("query", "string", required: true, order: 2),
    field("base", "string", order: 3)
  ]

  describe "positive control" do
    test "keyword args with atom keys coerce into a string-keyed body" do
      assert {:ok, %{"data" => %{"text" => "<a> <b> <c> ."}, "query" => "ASK {}"}} =
               Coerce.request("sparql", @fields, data: "<a> <b> <c> .", query: "ASK {}")
    end
  end

  describe "args shapes and keys" do
    test "map args with atom or string keys are equivalent" do
      a = Coerce.request("sparql", @fields, %{data: "x", query: "q"})
      b = Coerce.request("sparql", @fields, %{"data" => "x", "query" => "q"})
      c = Coerce.request("sparql", @fields, [{:data, "x"}, {"query", "q"}] |> Map.new())
      assert a == b
      assert a == c
    end

    test "nil for a non-required field is absent" do
      assert {:ok, body} = Coerce.request("sparql", @fields, data: "x", query: "q", base: nil)
      refute Map.has_key?(body, "base")
    end

    test "nil for a required field is missing" do
      assert {:error, %Refusal{code: :invalid_capability_request, details: %{"missing" => ["query"]}}} =
               Coerce.request("sparql", @fields, data: "x", query: nil)
    end

    test "non-map, non-keyword args refuse" do
      for bad <- ["x", 1, [1, 2], nil, {:a, 1}] do
        assert {:error,
                %Refusal{code: :invalid_capability_request, details: %{"type_errors" => [%{"field" => "args"}]}}} =
                 Coerce.request("sparql", @fields, bad)
      end
    end

    test "empty args on a no-field op is an empty body" do
      assert {:ok, %{}} == Coerce.request("capabilities", [], [])
      assert {:ok, %{}} == Coerce.request("capabilities", [], %{})
    end
  end

  describe "refusals" do
    test "unknown keys are listed sorted, and op is never accepted from args" do
      assert {:error, %Refusal{code: :invalid_capability_request, details: %{"unknown_keys" => ["op", "zzz"]}}} =
               Coerce.request("sparql", @fields, data: "x", query: "q", zzz: 1, op: "sniff")
    end

    test "missing required fields are listed in field order" do
      assert {:error, %Refusal{code: :invalid_capability_request, details: %{"missing" => ["data", "query"]}}} =
               Coerce.request("sparql", @fields, base: "b")
    end

    test "type errors carry field, expected and got" do
      assert {:error, %Refusal{code: :invalid_capability_request, details: %{"type_errors" => errors}}} =
               Coerce.request("sparql", @fields, data: "x", query: 12, base: [1])

      assert %{"field" => "query", "expected" => "string", "got" => "integer"} in errors
      assert %{"field" => "base", "expected" => "string", "got" => "list"} in errors
    end

    test "enum is never enforced client-side" do
      fields = [field("regime", "string", required: true, enum: ["simple", "rdf"])]
      assert {:ok, %{"regime" => "made-up"}} = Coerce.request("entail", fields, regime: "made-up")
    end
  end

  describe "types of the closed vocabulary" do
    @valid [
      {"string", "s", "s"},
      {"integer", 3, 3},
      {"boolean", false, false},
      {"object", %{a: 1, b: %{c: :d}}, %{"a" => 1, "b" => %{"c" => "d"}}},
      {"object", [a: 1], %{"a" => 1}},
      {"any", %{a: [1, %{b: nil}]}, %{"a" => [1, %{"b" => nil}]}},
      {"any", 5, 5},
      {"data_spec", "text", %{"text" => "text"}},
      {"data_spec", %{text: "t", dialect: :turtle, hint: nil}, %{"text" => "t", "dialect" => "turtle"}},
      {"data_spec", %{"text" => "t", "base" => "http://x/"}, %{"text" => "t", "base" => "http://x/"}},
      {"term", %{type: "uri", value: "http://x"}, %{"type" => "uri", "value" => "http://x"}},
      {"json_or_string", "{}", "{}"},
      {"json_or_string", %{a: 1}, %{"a" => 1}},
      {"json_or_string", [%{a: 1}], [%{"a" => 1}]},
      {"list<string>", ["a", "b"], ["a", "b"]},
      {"list<string>", [], []},
      {"list<object>", [%{a: 1}], [%{"a" => 1}]},
      {"list<any>", [1, "a", %{b: 2}], [1, "a", %{"b" => 2}]},
      {"list<term>", [%{type: "bnode", value: "b0"}], [%{"type" => "bnode", "value" => "b0"}]},
      {"list<list<string>>", [["a", "b"], []], [["a", "b"], []]},
      {"list<list<term>>", [[%{type: "uri", value: "u"}]], [[%{"type" => "uri", "value" => "u"}]]}
    ]

    for {{type, input, expected}, i} <- Enum.with_index(@valid) do
      test "#{type} accepts case #{i}" do
        fields = [field("f", unquote(type), required: true)]

        assert {:ok, %{"f" => unquote(Macro.escape(expected))}} ==
                 Coerce.request("op", fields, f: unquote(Macro.escape(input)))
      end
    end

    @invalid [
      {"string", 1},
      {"string", :atom},
      {"integer", "1"},
      {"integer", 1.5},
      {"boolean", "true"},
      {"object", "x"},
      {"object", 3},
      {"data_spec", 3},
      {"data_spec", %{"dialect" => "turtle"}},
      {"data_spec", %{"text" => 1}},
      {"data_spec", %{"text" => "t", "dialect" => 1}},
      {"term", "x"},
      {"json_or_string", 3},
      {"list<string>", "a"},
      {"list<string>", ["a", 1]},
      {"list<object>", [%{}, "x"]},
      {"list<term>", ["x"]},
      {"list<list<string>>", ["a"]},
      {"list<list<string>>", [["a", 2]]},
      {"list<list<term>>", [["x"]]}
    ]

    for {{type, input}, i} <- Enum.with_index(@invalid) do
      test "#{type} refuses case #{i}" do
        fields = [field("f", unquote(type), required: true)]

        assert {:error,
                %Refusal{
                  code: :invalid_capability_request,
                  details: %{"type_errors" => [%{"field" => "f", "expected" => unquote(type)}]}
                }} = Coerce.request("op", fields, f: unquote(Macro.escape(input)))
      end
    end
  end

  describe "stringify/1" do
    test "deep-stringifies maps, keyword lists and atom values" do
      assert Coerce.stringify(%{a: [%{b: :c}, [d: 1]], e: nil, f: true}) ==
               %{"a" => [%{"b" => "c"}, %{"d" => 1}], "e" => nil, "f" => true}
    end

    test "leaves strings, integers and plain lists alone" do
      assert Coerce.stringify(["a", 1, [2, "b"]]) == ["a", 1, [2, "b"]]
      assert Coerce.stringify([]) == []
    end

    test "is idempotent on a mixed structure" do
      once = Coerce.stringify(%{1 => "x", a: [%{b: :c}, [d: 1]]})
      assert Coerce.stringify(once) == once
    end
  end
end
