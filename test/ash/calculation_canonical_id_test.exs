# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine

defmodule AshGraphLaw.Ash.CalculationCanonicalIdTest do
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Calculation.CanonicalId
  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.Lifecycle.CanonOnly
  alias AshGraphLaw.Test.Lifecycle.Note
  alias AshGraphLaw.Test.Lifecycle.ShaclOnly

  @moduletag :wasm

  setup do
    start_pool!([])
    for resource <- [Note, CanonOnly, ShaclOnly], do: Ash.DataLayer.Ets.stop(resource)
    on_exit(fn -> for resource <- [Note, CanonOnly, ShaclOnly], do: Ash.DataLayer.Ets.stop(resource) end)
    :ok
  end

  defp seed(resource, title), do: resource |> Ash.Changeset.for_create(:seed, %{title: title}) |> Ash.create!()

  test "positive control: the id is a sha256 digest and is stable across loads" do
    note = seed(Note, "hello")
    first = Ash.load!(note, :canonical_id).canonical_id
    second = Ash.load!(note, :canonical_id).canonical_id
    assert "sha256:" <> hex = first
    assert hex =~ ~r/\A[0-9a-f]{64}\z/
    assert first == second
  end

  test "equal data yields equal ids and different data yields different ids" do
    a = seed(Note, "same")
    b = seed(Note, "same")
    c = seed(Note, "other")
    assert a.id != b.id
    assert Ash.load!(a, :canonical_id).canonical_id == Ash.load!(b, :canonical_id).canonical_id
    assert Ash.load!(a, :canonical_id).canonical_id != Ash.load!(c, :canonical_id).canonical_id
  end

  test "the default projection includes the primary key, so equal data on distinct records differs" do
    a = seed(Note, "same")
    b = seed(Note, "same")
    id_a = Ash.load!(a, :default_canonical_id).default_canonical_id
    assert "sha256:" <> _ = id_a
    assert id_a == Ash.load!(a, :default_canonical_id).default_canonical_id
    assert id_a != Ash.load!(b, :default_canonical_id).default_canonical_id
  end

  test "calculate/3 returns one id per record, in order" do
    records = [seed(Note, "a"), seed(Note, "b"), seed(Note, "a")]
    assert {:ok, [x, y, z]} = CanonicalId.calculate(records, [projection: AshGraphLaw.Test.Lifecycle.Projection], %{})
    assert x == z
    assert x != y
  end

  test "a declared canonical capability is allowed" do
    assert "sha256:" <> _ = Ash.load!(seed(CanonOnly, "x"), :canonical_id).canonical_id
  end

  test "a resource that does not declare canonical is refused before the engine is called" do
    assert {:error, error} = Ash.load(seed(ShaclOnly, "x"), :canonical_id)
    assert Error.codes(error) == [:capability_not_declared]
  end

  describe "init/1" do
    test "positive control: no options is valid" do
      assert {:ok, []} = CanonicalId.init([])
      assert {:ok, [timeout: 50]} = CanonicalId.init(timeout: 50)
    end

    test "unknown keys and bad types are rejected" do
      assert {:error, "unknown options: [:shapes]" <> _} = CanonicalId.init(shapes: "s")
      assert {:error, _} = CanonicalId.init(server: "pool")
      assert {:error, _} = CanonicalId.init(timeout: -1)
    end

    test "describe/1 names the capability" do
      assert CanonicalId.describe([]) =~ "canonical"
    end
  end
end
