# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.CanonicalTest do
  @moduledoc "Typed `canonical` against the REAL engine: stable id, N-Quads, data_spec coercion."
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Canonical, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "a data_spec is canonicalized to id, N-Quads and a quad count", %{opts: opts} do
      data = %{text: sample_turtle(), dialect: "turtle"}
      result = assert_typed_matches_raw("canonical", %{data: data}, opts)
      assert %Result{id: id, nquads: nquads, quads: 4} = result
      assert is_binary(id) and is_binary(nquads)
      assert nquads |> String.split("\n", trim: true) |> length() == 4
    end

    test "a bare binary means %{text: binary} and yields the same answer", %{opts: opts} do
      {:ok, spec} = API.canonical(%{data: %{text: sample_turtle()}}, opts)
      assert {:ok, bare} = API.canonical(%{data: sample_turtle()}, opts)
      assert bare.id == spec.id
      assert bare.nquads == spec.nquads
    end

    test "the canonical id is stable across dialects of the same graph", %{opts: opts} do
      {:ok, %{nquads: nq, id: id}} = API.canonical(%{data: %{text: sample_turtle()}}, opts)
      assert {:ok, %Result{id: ^id}} = API.canonical(%{data: %{text: nq, dialect: "nquads"}}, opts)
    end

    test "every ok example is typed", %{opts: opts} do
      for {example, result} <- run_examples("canonical", "ok", opts) do
        assert {:ok, %Result{quads: quads}} = result, example["id"]
        assert is_integer(quads)
      end
    end
  end

  describe "refusals" do
    test "missing data is a client refusal", %{opts: opts} do
      refusal = assert_refusal(API.canonical(%{}, opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["data"]
    end

    test "a data value of the wrong type is a client type error", %{opts: opts} do
      refusal = assert_refusal(API.canonical(%{data: 42}, opts), :invalid_capability_request)
      assert [%{"field" => "data", "expected" => "data_spec"}] = refusal.details["type_errors"]
    end

    test "unparsable data is an engine refusal", %{opts: opts} do
      assert_refusal(API.canonical(%{data: %{text: "not rdf at all {{{", dialect: "turtle"}}, opts), :engine_refused,
        kind: "EngineRejected"
      )
    end

    test "the engine refuses a raw string data field the client would have coerced", %{opts: opts} do
      example = example!("canonical.string-data-refused")
      assert {:error, refusal} = AshGraphLaw.call(example["request"], opts)
      assert refusal.kind == example["refusal_kind"]
    end
  end
end
