# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Unit.CapabilityDecodeTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago suite for the response decoding helper.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Capability.Decode
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Result.Term

  @uri %{"type" => "uri", "value" => "http://example.org/s"}
  @lit %{"type" => "literal", "value" => "1", "datatype" => "http://www.w3.org/2001/XMLSchema#integer"}

  defp term?(value), do: is_struct(value, Term)

  describe "positive control" do
    test "a response map decodes and a term column becomes a Term" do
      assert {:ok, %{"ok" => true} = map} = Decode.ensure_map(%{"ok" => true})
      assert term?(Decode.get(%{"t" => @uri}, "t", "term"))
      assert map["ok"]
    end
  end

  describe "ensure_map/1" do
    test "maps pass through unchanged" do
      m = %{"ok" => true, "x" => [1, 2]}
      assert {:ok, ^m} = Decode.ensure_map(m)
    end

    test "a JSON object binary decodes" do
      assert {:ok, %{"ok" => true}} = Decode.ensure_map(~s({"ok":true}))
    end

    test "everything else is :capability_response_undecodable" do
      for bad <- ["not json", "[1]", "3", 1, nil, [1], :atom, {:a}] do
        assert {:error, %Refusal{code: :capability_response_undecodable}} = Decode.ensure_map(bad)
      end
    end
  end

  describe "value/2" do
    test "nil is nil for every type" do
      for type <- ~w(string integer term list<term> list<list<term>> any nope) do
        assert Decode.value(nil, type) == nil
      end
    end

    test "term types produce Term structs" do
      assert term?(Decode.value(@uri, "term"))
      assert [t1, t2] = Decode.value([@uri, @lit], "list<term>")
      assert term?(t1) and term?(t2)

      assert [[a, nil], [b]] = Decode.value([[@uri, nil], [@lit]], "list<list<term>>")
      assert term?(a) and term?(b)
    end

    test "mismatched term shapes come back raw" do
      assert Decode.value("x", "term") == "x"
      assert Decode.value(3, "list<term>") == 3
      assert Decode.value(["x", 1], "list<term>") == ["x", 1]
      assert Decode.value(%{"a" => 1}, "list<list<term>>") == %{"a" => 1}
      assert [["x"], "row"] = Decode.value([["x"], "row"], "list<list<term>>")
    end

    test "every other vocabulary type passes through untouched" do
      values = [1, "s", true, %{"a" => [1]}, [1, "b"], [["a"]], [%{"k" => "v"}]]

      for type <- ~w(string integer boolean object any data_spec json_or_string list<string>
                     list<object> list<any> list<list<string>> unknown),
          value <- values do
        assert Decode.value(value, type) == value
      end
    end
  end

  describe "variant/3" do
    @tags ["solutions", "graph", "boolean"]

    test "known tags resolve to atoms" do
      assert Decode.variant(%{"kind" => "graph"}, "kind", @tags) == :graph
      assert Decode.variant(%{"kind" => "solutions"}, "kind", @tags) == :solutions
      assert Decode.variant(%{"kind" => "boolean"}, "kind", @tags) == :boolean
    end

    test "unknown, missing or malformed tags are {:unknown, string}" do
      assert Decode.variant(%{"kind" => "future"}, "kind", @tags) == {:unknown, "future"}
      assert Decode.variant(%{}, "kind", @tags) == {:unknown, ""}
      assert Decode.variant(%{"kind" => 3}, "kind", @tags) == {:unknown, ""}
      assert Decode.variant("nope", "kind", @tags) == {:unknown, ""}
      assert Decode.variant(%{"kind" => "graph"}, nil, @tags) == {:unknown, ""}
    end
  end

  describe "get/3" do
    test "reads and decodes by name; absent or non-map is nil" do
      assert Decode.get(%{"n" => 3}, "n", "integer") == 3
      assert Decode.get(%{}, "n", "integer") == nil
      assert Decode.get("x", "n", "integer") == nil
      assert Decode.get(nil, "n", "string") == nil
    end
  end
end
