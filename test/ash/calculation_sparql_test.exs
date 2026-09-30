# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine

defmodule AshGraphLaw.Ash.CalculationSparqlTest do
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Calculation.Sparql
  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.Lifecycle.CanonOnly
  alias AshGraphLaw.Test.Lifecycle.Note

  @moduletag :wasm

  setup do
    start_pool!([])
    for resource <- [Note, CanonOnly], do: Ash.DataLayer.Ets.stop(resource)
    on_exit(fn -> for resource <- [Note, CanonOnly], do: Ash.DataLayer.Ets.stop(resource) end)
    :ok
  end

  defp seed(resource, title), do: resource |> Ash.Changeset.for_create(:seed, %{title: title}) |> Ash.create!()

  test "positive control: SELECT returns one row map with the projected title" do
    note = seed(Note, "hello")
    assert [row] = Ash.load!(note, :titles).titles
    assert is_map(row)
    assert Map.values(row) == ["hello"]
  end

  test "terms: :raw keeps the engine term instead of its lexical value" do
    note = seed(Note, "hello")
    assert [row] = Ash.load!(note, :titles_raw).titles_raw
    assert [term] = Map.values(row)
    assert term_value(term) == "hello"
    assert is_map(term)
  end

  test "ASK returns a boolean and is false when the record has no title" do
    assert Ash.load!(seed(Note, "hello"), :titled?).titled? == true
    assert Ash.load!(seed(Note, nil), :titled?).titled? == false
  end

  test "CONSTRUCT returns the N-Quads text of the constructed graph" do
    nquads = Ash.load!(seed(Note, "hello"), :titled_graph).titled_graph
    assert is_binary(nquads)
    assert nquads =~ "lifecycle:label"
    assert nquads =~ "hello"
  end

  test "a record with no matching solution yields an empty row list" do
    assert Ash.load!(seed(Note, nil), :titles).titles == []
  end

  test "calculate/3 returns one value per record, in order" do
    records = [seed(Note, "a"), seed(Note, "b")]
    query = "SELECT ?t WHERE { ?s <urn:ash-graphlaw:lifecycle:title> ?t }"

    assert {:ok, [[%{} = first], [%{} = second]]} =
             Sparql.calculate(records, [query: query, projection: AshGraphLaw.Test.Lifecycle.Projection], %{})

    assert Map.values(first) == ["a"]
    assert Map.values(second) == ["b"]
  end

  test "a malformed query is an engine refusal carried as a typed error" do
    assert {:error, error} = Ash.load(seed(Note, "x"), :malformed)
    assert [code | _] = Error.codes(error)
    assert code in AshGraphLaw.Refusal.codes()
    assert Error.raws(error) != []
  end

  test "a resource that does not declare sparql is refused before the engine is called" do
    assert {:error, error} = Ash.load(seed(CanonOnly, "x"), :titled?)
    assert Error.codes(error) == [:capability_not_declared]
  end

  describe "init/1" do
    test "positive control: a query is enough" do
      assert {:ok, opts} = Sparql.init(query: "ASK {}", terms: :raw)
      assert opts[:terms] == :raw
    end

    test "missing query, bad terms and unknown keys are rejected" do
      assert {:error, "missing required options: [:query]"} = Sparql.init([])
      assert {:error, _} = Sparql.init(query: "ASK {}", terms: :bogus)
      assert {:error, _} = Sparql.init(query: "")
      assert {:error, "unknown options: [:shapes]" <> _} = Sparql.init(query: "ASK {}", shapes: "s")
    end

    test "describe/1 names the query" do
      assert Sparql.describe(query: "ASK {}") =~ "ASK {}"
    end
  end

  defp term_value(%{value: value}), do: value
  defp term_value(%{"value" => value}), do: value
end
