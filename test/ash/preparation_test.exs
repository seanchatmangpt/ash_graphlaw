# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.PreparationFixtures.NoteLaw do
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

defmodule AshGraphLaw.Test.PreparationFixtures.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Test.PreparationFixtures.Note
  end
end

defmodule AshGraphLaw.Test.PreparationFixtures.Note do
  @moduledoc false
  use Ash.Resource,
    domain: AshGraphLaw.Test.PreparationFixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read, create: [:title]]

    read :checked do
      prepare {AshGraphLaw.Preparation.Admit, admission: :note_shape}
    end

    action :check, :boolean do
      argument :title, :string, public?: true
      prepare {AshGraphLaw.Preparation.Admit, admission: :note_shape}
      run fn _input, _context -> {:ok, true} end
    end
  end

  graphlaw do
    runtime(timeout_ms: 5000)
    admission(:note_shape, step: :shacl, ceiling: :observe, law: AshGraphLaw.Test.PreparationFixtures.NoteLaw)
  end
end

defmodule AshGraphLaw.Ash.PreparationTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test against the real wasm engine.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.PreparationFixtures.Note

  @moduletag :wasm

  setup do
    start_pool!([])
    Ash.DataLayer.Ets.stop(Note)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Note) end)
    {:ok, _} = Note |> Ash.Changeset.for_create(:create, %{title: "seed"}) |> Ash.create()
    :ok
  end

  describe "generic action input" do
    test "a conformant input runs the action" do
      assert {:ok, true} = Note |> Ash.ActionInput.for_action(:check, %{title: "ok"}) |> Ash.run_action()
    end

    test "a violating input is refused by the engine (:engine_refused) and the action does not run" do
      assert {:ok, true} = Note |> Ash.ActionInput.for_action(:check, %{title: "control"}) |> Ash.run_action()

      input = Ash.ActionInput.for_action(Note, :check, %{})
      refute input.valid?
      assert Error.codes(input.errors) == [:engine_refused]
      assert {:error, error} = Ash.run_action(input)
      assert Error.codes(error) == [:engine_refused]
    end
  end

  describe "read query" do
    test "a conformant query reads the stored records" do
      query = Ash.Query.for_read(Note, :checked, %{}, context: %{title: "ok"})
      assert query.valid?
      assert [%{title: "seed"}] = Ash.read!(query)
    end

    test "a violating query is refused by the engine (:engine_refused) and returns no records" do
      control = Ash.Query.for_read(Note, :checked, %{}, context: %{title: "ok"})
      assert [_] = Ash.read!(control)

      query = Ash.Query.for_read(Note, :checked, %{})
      refute query.valid?
      assert Error.codes(query.errors) == [:engine_refused]
      assert {:error, error} = Ash.read(query)
      assert Error.codes(error) == [:engine_refused]
    end
  end
end
