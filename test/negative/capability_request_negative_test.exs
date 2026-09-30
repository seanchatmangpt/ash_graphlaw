# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written negative court over typed request validation.

defmodule AshGraphLaw.Negative.CapabilityRequestNegativeTest do
  @moduledoc """
  Request validation refusals of every typed capability, with exact `details`: missing required
  fields, unknown keys (including `op`), type errors, unusable args. No engine is started: every
  refusal here happens client-side, before a byte reaches a host, which the last describe proves by
  pointing the calls at a server that does not exist and still getting `:invalid_capability_request`.
  """
  use ExUnit.Case, async: true

  import AshGraphLaw.Test.CapabilityCase,
    only: [
      registry: 0,
      op_names: 0,
      registry_op: 1,
      examples_for: 1,
      args_of: 1,
      built: 2,
      typed: 3,
      capability: 1
    ]

  alias AshGraphLaw.Refusal

  # A wrong value per registry type and the `got` name the refusal must report.
  @wrong %{
    "string" => {5, "integer"},
    "integer" => {"5", "string"},
    "boolean" => {"true", "string"},
    "object" => {"str", "string"},
    "data_spec" => {5, "integer"},
    "json_or_string" => {5, "integer"},
    "list<string>" => {"str", "string"},
    "list<object>" => {"str", "string"},
    "list<list<string>>" => {"str", "string"}
  }

  defp base_args(op) do
    example = Enum.find(examples_for(op), &(&1["outcome"] == "ok"))
    args_of(example)
  end

  defp fields(op), do: registry_op(op)["request"]["fields"]
  defp required(op), do: for(f <- fields(op), f["required"], do: f["name"])
  defp refusal!({:error, %Refusal{} = refusal}), do: refusal

  describe "positive control" do
    test "every op builds its request from its first ok example, injecting op and nothing else" do
      for op <- op_names() do
        args = base_args(op)
        assert {:ok, request} = built(op, args), op
        assert request["op"] == op
        names = Enum.map(fields(op), & &1["name"])
        assert (Map.keys(request) -- ["op"]) -- names == [], "#{op}: request has keys outside the registry fields"

        for name <- required(op), do: assert(Map.has_key?(request, name), "#{op}: #{name} lost")
      end
    end

    test "the registry names every op module and the module exports the behaviour" do
      for op <- op_names() do
        module = capability(op)
        assert Code.ensure_loaded?(module), "#{inspect(module)} missing"

        for {fun, arity} <- [op: 0, build_request: 1, decode: 1, run: 2] do
          assert function_exported?(module, fun, arity), "#{inspect(module)}.#{fun}/#{arity}"
        end

        assert module.op() == op
      end
    end

    test "atom keys, string keys and keyword lists build the same request" do
      args = %{"text" => "x"}
      assert built("sniff", args) == built("sniff", %{text: "x"})
      assert built("sniff", args) == built("sniff", text: "x")
    end
  end

  describe "missing required fields" do
    test "dropping each required field names exactly that field" do
      for op <- op_names(), name <- required(op) do
        args = op |> base_args() |> Map.delete(name)
        refusal = refusal!(built(op, args))
        assert refusal.code == :invalid_capability_request, "#{op}/#{name}"
        assert refusal.details["missing"] == [name], "#{op}/#{name}: #{inspect(refusal.details)}"
        assert refusal.raw == nil
        assert refusal.class == :refused_structure
      end
    end

    test "empty args name every required field" do
      for op <- op_names(), required(op) != [] do
        refusal = refusal!(built(op, %{}))
        assert Enum.sort(refusal.details["missing"]) == Enum.sort(required(op)), op
      end
    end

    test "a nil for a required field counts as missing; a nil for an optional field counts as absent" do
      assert %{details: %{"missing" => ["text"]}} = refusal!(built("sniff", %{text: nil}))
      assert {:ok, request} = built("sniff", %{text: "x", hint: nil})
      refute Map.has_key?(request, "hint")
    end
  end

  describe "unknown keys" do
    test "an unknown key is listed, sorted, for every op" do
      for op <- op_names() do
        args = op |> base_args() |> Map.put("zz_extra", 1) |> Map.put("aa_extra", 2)
        refusal = refusal!(built(op, args))
        assert refusal.code == :invalid_capability_request, op
        assert refusal.details["unknown_keys"] == ["aa_extra", "zz_extra"], op
      end
    end

    test "the op key is never accepted from args, even with the right value" do
      for op <- op_names() do
        args = op |> base_args() |> Map.put("op", op)
        assert %{details: %{"unknown_keys" => ["op"]}} = refusal!(built(op, args)), op

        assert %{details: %{"unknown_keys" => ["op"]}} = refusal!(built(op, Map.delete(args, "op") |> Map.put(:op, op))),
               op
      end
    end

    test "a key of another op is unknown here" do
      assert %{details: %{"unknown_keys" => ["query"]}} = refusal!(built("sniff", %{text: "x", query: "ASK {}"}))
    end
  end

  describe "type errors" do
    test "a wrong value for each field of each op is reported with expected and got" do
      for op <- op_names(), field <- fields(op), {bad, got} <- [Map.get(@wrong, field["type"])], not is_nil(got) do
        args = Map.put(base_args(op), field["name"], bad)
        refusal = refusal!(built(op, args))
        assert refusal.code == :invalid_capability_request, "#{op}/#{field["name"]}"

        assert %{"field" => field["name"], "expected" => field["type"], "got" => got} in refusal.details["type_errors"],
               "#{op}/#{field["name"]}: #{inspect(refusal.details)}"
      end
    end

    test "several type errors are reported together, in registry field order" do
      refusal = refusal!(built("parse", %{text: 1, dialect: 2}))

      assert refusal.details["type_errors"] == [
               %{"field" => "text", "expected" => "string", "got" => "integer"},
               %{"field" => "dialect", "expected" => "string", "got" => "integer"}
             ]
    end

    test "a data_spec map without text is a type error, a bare binary is not" do
      assert %{details: %{"type_errors" => [%{"field" => "data", "expected" => "data_spec"}]}} =
               refusal!(built("canonical", %{data: %{dialect: "turtle"}}))

      assert {:ok, %{"data" => %{"text" => "x"}}} = built("canonical", %{data: "x"})
    end

    test "list element errors make the whole list a type error" do
      refusal = refusal!(built("datalog", %{rules: [], facts: [["a", "b", 3]]}))
      assert [%{"field" => "facts", "expected" => "list<list<string>>"}] = refusal.details["type_errors"]
    end

    test "unusable args are refused with an args type error" do
      for bad <- ["text", 5, {:a, 1}, [1, 2], self()] do
        refusal = refusal!(built("sniff", bad))
        assert refusal.code == :invalid_capability_request
        assert [%{"field" => "args", "expected" => "map"}] = refusal.details["type_errors"]
      end
    end
  end

  describe "enum is informational" do
    test "an out-of-enum value builds a request (the engine decides)" do
      for op <- op_names(), field <- fields(op), is_list(field["enum"]), field["type"] == "string" do
        args = Map.put(base_args(op), field["name"], "definitely-not-#{field["name"]}")
        assert {:ok, request} = built(op, args), "#{op}/#{field["name"]}"
        assert request[field["name"]] == "definitely-not-#{field["name"]}"
      end
    end
  end

  describe "refused before the host is reached" do
    test "every refusal above is returned even when the named server does not exist" do
      opts = [server: :no_such_graphlaw_host]

      for op <- op_names(), required(op) != [] do
        assert {:error, %Refusal{code: :invalid_capability_request}} = typed(op, %{}, opts), op
      end
    end

    test "an unknown capability name through API.run/3 is :unknown_capability" do
      assert {:error, %Refusal{code: :unknown_capability} = refusal} =
               AshGraphLaw.Capability.API.run("teleport", %{}, server: :no_such_graphlaw_host)

      assert refusal.raw == nil
    end

    test "the registry declares every request type this file knows how to break" do
      types =
        for op <- op_names(), field <- fields(op), into: MapSet.new(), do: field["type"]

      known = MapSet.new(Map.keys(@wrong) ++ ["any", "term"])
      assert MapSet.difference(types, known) == MapSet.new(), "untested request field types"
      assert registry()["schema"] == "graphlaw.capability-registry/1"
    end
  end
end
