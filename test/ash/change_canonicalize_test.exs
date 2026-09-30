# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine

defmodule AshGraphLaw.Ash.ChangeCanonicalizeTest do
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Change.Canonicalize
  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.Lifecycle.Note
  alias AshGraphLaw.Test.Lifecycle.ShaclOnly

  @moduletag :wasm

  setup do
    start_pool!([])
    for resource <- [Note, ShaclOnly], do: Ash.DataLayer.Ets.stop(resource)
    on_exit(fn -> for resource <- [Note, ShaclOnly], do: Ash.DataLayer.Ets.stop(resource) end)
    :ok
  end

  defp canonicalize(title),
    do: Note |> Ash.Changeset.for_create(:canonicalize, %{title: title}) |> Ash.create!()

  test "positive control: the canonical id is written to the attribute and persisted" do
    note = canonicalize("hello")
    assert "sha256:" <> hex = note.graph_id
    assert hex =~ ~r/\A[0-9a-f]{64}\z/
    assert Ash.get!(Note, note.id).graph_id == note.graph_id
  end

  test "equal data gives equal ids and different data different ids" do
    assert canonicalize("same").graph_id == canonicalize("same").graph_id
    assert canonicalize("same").graph_id != canonicalize("other").graph_id
  end

  test "the id agrees with the canonical id calculation over the stored record" do
    note = canonicalize("hello")
    assert Ash.load!(note, :canonical_id).canonical_id == note.graph_id
  end

  test "the id does not depend on the attribute's previous value" do
    note = canonicalize("hello")
    assert "sha256:" <> _ = note.graph_id

    assert {:ok, again} = note |> Ash.Changeset.for_update(:recanonicalize, %{}) |> Ash.update()
    assert again.graph_id == note.graph_id

    assert {:ok, renamed} = note |> Ash.Changeset.for_update(:recanonicalize, %{title: "other"}) |> Ash.update()
    assert renamed.graph_id != note.graph_id
  end

  test "a resource that does not declare canonical gets a refusal on the changeset and stores nothing" do
    changeset = Ash.Changeset.for_create(ShaclOnly, :canonicalize, %{title: "x"})
    assert {:error, %Ash.Error.Invalid{} = error} = Ash.create(changeset)
    assert Error.codes(error) == [:capability_not_declared]
    assert Ash.read!(ShaclOnly) == []
  end

  describe "callbacks" do
    test "positive control: init/1 defaults the lease key" do
      assert {:ok, opts} = Canonicalize.init(attribute: :graph_id)
      assert opts[:lease_key] == :graphlaw_lease
    end

    test "init/1 rejects a missing attribute, unknown keys and bad types" do
      assert {:error, "missing required options: [:attribute]"} = Canonicalize.init([])
      assert {:error, _} = Canonicalize.init(attribute: "graph_id")
      assert {:error, "unknown options: [:shapes]" <> _} = Canonicalize.init(attribute: :graph_id, shapes: "s")
    end

    test "atomic/3 is non-atomic with the documented reason and needs no engine" do
      assert {:not_atomic, "GraphLaw canonicalization requires a WASM call"} =
               Canonicalize.atomic(Ash.Changeset.new(Note), [attribute: :graph_id], %{})
    end

    test "change/3 leaves other action types untouched" do
      changeset = Ash.Changeset.new(Note)
      read = %{changeset | action_type: :read}
      assert Canonicalize.change(read, [attribute: :graph_id], %{}) == read
    end
  end

  test "bulk update with strategy :atomic is refused because the change is not atomic" do
    notes = for title <- ["a", "b"], do: canonicalize(title)

    # positive control: the stream strategy runs the change per record
    assert %Ash.BulkResult{status: :success} =
             Ash.bulk_update(notes, :recanonicalize, %{}, strategy: :stream, return_errors?: true)

    result = Ash.bulk_update(Note, :recanonicalize, %{}, strategy: :atomic, return_errors?: true)
    refute match?(%Ash.BulkResult{status: :success}, result)
    assert inspect(result) =~ "GraphLaw canonicalization requires a WASM call"
  end
end
