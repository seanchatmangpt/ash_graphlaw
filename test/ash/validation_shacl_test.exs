# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine

defmodule AshGraphLaw.Ash.ValidationShaclTest do
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.Lifecycle.CanonOnly
  alias AshGraphLaw.Test.Lifecycle.Note
  alias AshGraphLaw.Validation.Shacl
  alias AshGraphLaw.Validation.Shacl.NonConformance

  @moduletag :wasm

  setup do
    start_pool!([])
    for resource <- [Note, CanonOnly], do: Ash.DataLayer.Ets.stop(resource)
    on_exit(fn -> for resource <- [Note, CanonOnly], do: Ash.DataLayer.Ets.stop(resource) end)
    :ok
  end

  defp non_conformances(%{errors: errors}), do: Enum.filter(errors, &match?(%NonConformance{}, &1))

  test "positive control: a conforming changeset validates and is persisted" do
    changeset = Ash.Changeset.for_create(Note, :write, %{title: "hello"})
    assert changeset.valid?
    assert {:ok, note} = Ash.create(changeset)
    assert note.title == "hello"
    assert [%{id: id}] = Ash.read!(Note)
    assert id == note.id
  end

  test "a nonconforming changeset fails with the SHACL results and persists nothing" do
    changeset = Ash.Changeset.for_create(Note, :write, %{})
    refute changeset.valid?
    assert [%NonConformance{results: [_ | _] = results, resource: Note}] = non_conformances(changeset)
    assert Enum.all?(results, &is_map/1)
    assert Error.codes(changeset.errors) == []

    assert {:error, %Ash.Error.Invalid{}} = Ash.create(changeset)
    assert Ash.read!(Note) == []
  end

  test "an update that breaks the shape is rejected and the record is unchanged" do
    note = Note |> Ash.Changeset.for_create(:seed, %{title: "before"}) |> Ash.create!()

    assert {:ok, renamed} = note |> Ash.Changeset.for_update(:rename, %{title: "after"}) |> Ash.update()
    assert renamed.title == "after"

    changeset = Ash.Changeset.for_update(renamed, :rename, %{title: ""})
    refute changeset.valid?
    assert [%NonConformance{}] = non_conformances(changeset)
    assert Ash.get!(Note, note.id).title == "after"
  end

  test "a shapes graph the engine refuses surfaces as a typed refusal, not a conformance error" do
    changeset = Ash.Changeset.for_create(Note, :write_broken, %{title: "x"})
    refute changeset.valid?
    assert non_conformances(changeset) == []
    assert [code | _] = Error.codes(changeset.errors)
    assert code in AshGraphLaw.Refusal.codes()
  end

  test "a resource that does not declare shacl is refused before the engine is called" do
    changeset = Ash.Changeset.for_create(CanonOnly, :write, %{title: "x"})
    refute changeset.valid?
    assert Error.codes(changeset.errors) == [:capability_not_declared]
  end

  describe "callbacks" do
    test "positive control: init/1 defaults the lease key and keeps the shapes" do
      assert {:ok, opts} = Shacl.init(shapes: "s")
      assert opts[:shapes] == "s"
      assert opts[:lease_key] == :graphlaw_lease
    end

    test "init/1 rejects missing shapes, unknown keys and bad types" do
      assert {:error, "missing required options: [:shapes]"} = Shacl.init([])
      assert {:error, "unknown options: [:admission]" <> _} = Shacl.init(shapes: "s", admission: :x)
      assert {:error, _} = Shacl.init(shapes: "s", timeout: 0)
      assert {:error, _} = Shacl.init(shapes: "s", message: :not_a_string)
    end

    test "atomic/3 is non-atomic with the documented reason and needs no engine" do
      assert {:not_atomic, "GraphLaw SHACL validation requires a WASM call"} =
               Shacl.atomic(Ash.Changeset.new(Note), [shapes: "s"], %{})
    end

    test "supports/1 and describe/1" do
      assert Shacl.supports(shapes: "s") == [Ash.Changeset]
      assert [message: message, vars: []] = Shacl.describe(shapes: "s")
      assert message =~ "SHACL"
    end

    test "NonConformance messages" do
      assert Exception.message(NonConformance.exception(results: [%{}, %{}])) =~ "2 result(s)"
      assert Exception.message(NonConformance.exception(detail: "custom")) == "custom"
      assert Exception.message(NonConformance.exception([])) =~ "non-conformance"
    end
  end

  test "bulk update with strategy :atomic is refused because the validation is not atomic" do
    notes = for title <- ["a", "b"], do: Note |> Ash.Changeset.for_create(:seed, %{title: title}) |> Ash.create!()

    # positive control: the stream strategy runs the validation per record
    assert %Ash.BulkResult{status: :success} =
             Ash.bulk_update(notes, :rename, %{title: "z"}, strategy: :stream, return_errors?: true)

    result = Ash.bulk_update(Note, :rename, %{title: "y"}, strategy: :atomic, return_errors?: true)
    refute match?(%Ash.BulkResult{status: :success}, result)
    assert inspect(result) =~ "GraphLaw SHACL validation requires a WASM call"
    assert Enum.all?(Ash.read!(Note), &(&1.title == "z"))
  end
end
