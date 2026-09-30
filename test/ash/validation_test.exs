# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.ValidationFixtures.NoteLaw do
  @moduledoc false
  # UNSUPPORTED(generator-capability): inline law fixture with its own N-Triples projection.
  @behaviour AshGraphLaw.Law

  @shapes "@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix t: <urn:t:> . " <>
            "t:NoteShape a sh:NodeShape ; sh:targetClass t:Note ; sh:property [ sh:path t:title ; sh:minCount 1 ] ."

  @impl true
  def steps(_subject, _admission), do: [%{"step" => "shacl", "shapes" => @shapes}]

  @impl true
  def data(subject, _admission) do
    type = "<urn:t:n> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:t:Note> .\n"

    title =
      case title_of(subject) do
        nil -> ""
        value -> "<urn:t:n> <urn:t:title> \"#{escape(value)}\" .\n"
      end

    {:ok, %{text: type <> title, dialect: "ntriples"}}
  end

  defp title_of(%Ash.Changeset{} = changeset), do: Ash.Changeset.get_attribute(changeset, :title)
  defp title_of(%Ash.ActionInput{} = input), do: Ash.ActionInput.get_argument(input, :title)
  defp title_of(%Ash.Query{context: context}), do: Map.get(context, :title)

  defp escape(value), do: value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
end

defmodule AshGraphLaw.Test.ValidationFixtures.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Test.ValidationFixtures.Note
  end
end

defmodule AshGraphLaw.Test.ValidationFixtures.Note do
  @moduledoc false
  use Ash.Resource,
    domain: AshGraphLaw.Test.ValidationFixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]

    create :write do
      accept [:title]
      validate {AshGraphLaw.Validation.Admissible, admission: :note_shape}
    end
  end

  graphlaw do
    runtime(timeout_ms: 5000)
    admission(:note_shape, step: :shacl, ceiling: :observe, law: AshGraphLaw.Test.ValidationFixtures.NoteLaw)
  end
end

defmodule AshGraphLaw.Ash.ValidationTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.ValidationFixtures.Note
  alias AshGraphLaw.Validation.Admissible

  @moduletag :wasm

  setup do
    start_pool!([])
    Ash.DataLayer.Ets.stop(Note)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Note) end)
    :ok
  end

  test "a conformant changeset passes validation and is persisted" do
    assert {:ok, note} = Note |> Ash.Changeset.for_create(:write, %{title: "hello"}) |> Ash.create()
    assert note.title == "hello"
    assert [%{id: id}] = Ash.read!(Note)
    assert id == note.id
  end

  test "a violating changeset fails validation with :not_admitted and persists nothing" do
    assert {:ok, _} = Note |> Ash.Changeset.for_create(:write, %{title: "control"}) |> Ash.create()
    Ash.DataLayer.Ets.stop(Note)

    changeset = Ash.Changeset.for_create(Note, :write, %{})
    refute changeset.valid?
    assert Error.codes(changeset.errors) == [:engine_refused]

    assert {:error, %Ash.Error.Invalid{} = error} = Ash.create(changeset)
    assert Error.codes(error) == [:engine_refused]
    assert Ash.read!(Note) == []
  end

  test "the validation is non-atomic and leaves no evidence in the changeset context" do
    assert {:not_atomic, _reason} = Admissible.atomic(Ash.Changeset.new(Note), [admission: :note_shape], %{})
    changeset = Ash.Changeset.for_create(Note, :write, %{title: "x"})
    assert changeset.valid?
    refute Map.has_key?(changeset.context, :graphlaw)
  end
end
