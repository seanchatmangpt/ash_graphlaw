# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine

defmodule AshGraphLaw.Ash.CalculationConformsTest do
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Calculation.Conforms
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

  test "positive control: a conforming record calculates true" do
    note = seed(Note, "hello")
    assert Ash.load!(note, :conforms?).conforms? == true
  end

  test "calculate/3 returns one boolean per record, in order" do
    records = [seed(Note, "a"), seed(Note, ""), seed(Note, "c")]
    assert {:ok, [true, false, true]} = Conforms.calculate(records, opts(), %{})
  end

  test "a nonconforming record calculates false" do
    assert Ash.load!(seed(Note, ""), :conforms?).conforms? == false
    assert Ash.load!(seed(Note, nil), :conforms?).conforms? == false
  end

  test "a resource that does not declare shacl is refused before the engine is called" do
    assert {:error, error} = Ash.load(seed(CanonOnly, "x"), :conforms?)
    assert Error.codes(error) == [:capability_not_declared]
  end

  test "an engine refusal surfaces as an error carrying the typed refusal" do
    assert {:error, error} = Ash.load(seed(Note, "x"), :broken_conforms?)
    assert [code | _] = Error.codes(error)
    assert code in AshGraphLaw.Refusal.codes()
    assert Error.raws(error) != []
  end

  describe "init/1" do
    test "positive control: valid options are returned" do
      assert {:ok, opts} = Conforms.init(shapes: "s", timeout: 100)
      assert opts[:shapes] == "s"
    end

    test "missing shapes, unknown keys and bad types are rejected" do
      assert {:error, "missing required options: [:shapes]"} = Conforms.init([])
      assert {:error, "unknown options: [:bogus]" <> _} = Conforms.init(shapes: "s", bogus: 1)
      assert {:error, _} = Conforms.init(shapes: "")
      assert {:error, _} = Conforms.init(shapes: "s", timeout: 0)
      assert {:error, _} = Conforms.init(shapes: "s", projection: "Mod")
      assert {:error, "options must be a keyword list"} = Conforms.init(:nope)
    end

    test "describe/1 names the capability" do
      assert Conforms.describe(shapes: "s") =~ "SHACL"
    end
  end

  defp opts, do: [projection: AshGraphLaw.Test.Lifecycle.Projection, shapes: shapes()]

  defp shapes do
    "@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix t: <urn:ash-graphlaw:lifecycle:> . " <>
      "t:S a sh:NodeShape ; sh:targetClass t:Note ; sh:property [ sh:path t:title ; sh:minCount 1 ; sh:minLength 1 ] ."
  end
end
