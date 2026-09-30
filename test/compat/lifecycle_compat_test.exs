# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Compat.LifecycleFixtures.DefaultShapeLaw do
  @moduledoc false
  # UNSUPPORTED(generator-capability): inline law fixture. No data/2: the admission's projection
  # (AshGraphLaw.Projection.Default) supplies the graph. The shape requires an `attr:title` triple
  # on every changeset subject and an `arg:title` triple on every action-input subject.
  @behaviour AshGraphLaw.Law

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  <urn:compat:ChangeShape> a sh:NodeShape ;
    sh:targetSubjectsOf <urn:ash-graphlaw:actionType> ;
    sh:property [ sh:path <urn:ash-graphlaw:attr:title> ; sh:minCount 1 ] .
  """

  @arg_shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  <urn:compat:InputShape> a sh:NodeShape ;
    sh:targetSubjectsOf <urn:ash-graphlaw:actionType> ;
    sh:property [ sh:path <urn:ash-graphlaw:arg:title> ; sh:minCount 1 ] .
  """

  @impl true
  def steps(%Ash.ActionInput{}, _admission), do: [%{"step" => "shacl", "shapes" => @arg_shapes}]
  def steps(_subject, _admission), do: [%{"step" => "shacl", "shapes" => @shapes}]
end

defmodule AshGraphLaw.Compat.LifecycleFixtures.StableLaw do
  @moduledoc false
  # UNSUPPORTED(generator-capability): inline law fixture whose own projection omits the generated id, so
  # two creates of the same title project to byte-identical data.
  @behaviour AshGraphLaw.Law

  @shapes "@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix t: <urn:t:> . " <>
            "t:NoteShape a sh:NodeShape ; sh:targetClass t:Note ; sh:property [ sh:path t:title ; sh:minCount 1 ] ."

  @impl true
  def steps(_subject, _admission), do: [%{"step" => "shacl", "shapes" => @shapes}]

  @impl true
  def data(%Ash.Changeset{} = changeset, _admission) do
    type = "<urn:t:n> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:t:Note> .\n"

    title =
      case Ash.Changeset.get_attribute(changeset, :title) do
        nil -> ""
        value -> "<urn:t:n> <urn:t:title> \"#{value}\" .\n"
      end

    {:ok, %{text: type <> title, dialect: "ntriples"}}
  end
end

defmodule AshGraphLaw.Compat.LifecycleFixtures.QueryLaw do
  @moduledoc false
  # UNSUPPORTED(generator-capability): inline law fixture with its own N-Triples projection for read queries.
  @behaviour AshGraphLaw.Law

  @shapes "@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix t: <urn:t:> . " <>
            "t:NoteShape a sh:NodeShape ; sh:targetClass t:Note ; sh:property [ sh:path t:title ; sh:minCount 1 ] ."

  @impl true
  def steps(_subject, _admission), do: [%{"step" => "shacl", "shapes" => @shapes}]

  @impl true
  def data(%Ash.Query{context: context}, _admission) do
    type = "<urn:t:n> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:t:Note> .\n"

    title =
      case Map.get(context, :title) do
        nil -> ""
        value -> "<urn:t:n> <urn:t:title> \"#{value}\" .\n"
      end

    {:ok, %{text: type <> title, dialect: "ntriples"}}
  end

  def data(_subject, _admission), do: :default
end

defmodule AshGraphLaw.Compat.LifecycleFixtures.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Compat.LifecycleFixtures.Note
  end
end

defmodule AshGraphLaw.Compat.LifecycleFixtures.Note do
  @moduledoc false
  # Uses Change.Admit, Validation.Admissible and Preparation.Admit against the ORIGINAL :admission DSL
  # and declares NO capability entity.
  use Ash.Resource,
    domain: AshGraphLaw.Compat.LifecycleFixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  alias AshGraphLaw.Compat.LifecycleFixtures.{DefaultShapeLaw, QueryLaw, StableLaw}

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]

    create :open do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :shape}
    end

    create :open_stable do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :stable}
    end

    create :write do
      accept [:title]
      validate {AshGraphLaw.Validation.Admissible, admission: :shape}
    end

    create :derive do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :derive}
    end

    create :seed do
      accept [:title]
    end

    read :checked do
      prepare {AshGraphLaw.Preparation.Admit, admission: :query_shape}
    end

    action :check, :boolean do
      argument :title, :string, public?: true
      prepare {AshGraphLaw.Preparation.Admit, admission: :shape}
      run fn _input, _context -> {:ok, true} end
    end
  end

  graphlaw do
    runtime do
      timeout_ms(5000)
      trusted_keys([AshGraphLaw.Test.Lease.public_key_hex(:trusted)])
    end

    admission(:shape, step: :shacl, ceiling: :observe, law: DefaultShapeLaw)
    admission(:stable, step: :shacl, ceiling: :observe, law: StableLaw)
    admission(:query_shape, step: :shacl, ceiling: :observe, law: QueryLaw)
    admission(:derive, step: :rdfs, ceiling: :construct)
  end
end

defmodule AshGraphLaw.Compat.LifecycleCompatTest do
  @moduledoc """
  The lifecycle integrations (`Change.Admit`, `Validation.Admissible`, `Preparation.Admit`), a `Law`
  module and `Projection.Default` keep admitting and refusing exactly as pinned by `test/ash/**`,
  driven through the REAL pool and engine, on a resource that declares no capability entity.

  UNSUPPORTED(generator-capability): hand-written Chicago test.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Compat.LifecycleFixtures.Note
  alias AshGraphLaw.{Admissions, Error, Evidence}
  alias AshGraphLaw.Projection.Default
  alias AshGraphLaw.Test.Lease

  @moduletag :wasm

  # Engines from v26.9.29 tag SHACL violations details.code "NotAdmitted" (-> :not_admitted); older engines
  # return the bare EngineRejected kind (-> :engine_refused) with the same message and class of failure.
  # The pinned v26.9.28 engine is the older shape; a bump flips this helper, never the assertions.
  defp violation_codes do
    {:ok, %{"ops" => ops}} = AshGraphLaw.capabilities()
    if "policy" in ops, do: [:not_admitted], else: [:engine_refused]
  end

  setup do
    start_pool!([])
    Ash.DataLayer.Ets.stop(Note)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Note) end)
    :ok
  end

  defp create_capturing(action, params, context \\ %{}) do
    parent = self()

    Note
    |> Ash.Changeset.for_create(action, params, context: context)
    |> Ash.Changeset.after_action(fn changeset, record ->
      send(parent, {:context, changeset.context})
      {:ok, record}
    end)
    |> Ash.create()
  end

  test "the fixture declares no capability entity" do
    assert Admissions.capabilities(Note) == []
    assert [:shape, :stable, :query_shape, :derive] == Enum.map(Admissions.all(Note), & &1.name)
  end

  describe "Change.Admit with a Law and Projection.Default" do
    test "positive control: a titled create is admitted, persisted and carries PARTIAL_ALIVE evidence" do
      assert {:ok, note} = create_capturing(:open, %{title: "Fix the build"})
      assert_receive {:context, %{graphlaw: %Evidence{} = evidence}}

      assert evidence.admission == :shape
      assert evidence.standing == :PARTIAL_ALIVE
      refute evidence.standing == :ALIVE
      assert byte_size(evidence.digest) == 64
      assert byte_size(evidence.input_digest) == 64
      assert evidence.digest == Evidence.digest(evidence)
      assert [%{id: id}] = Ash.read!(Note)
      assert id == note.id
    end

    test "evidence is deterministic in the input (own projection) and changes when the input changes" do
      assert {:ok, _} = create_capturing(:open_stable, %{title: "Stable"})
      assert_receive {:context, %{graphlaw: first}}
      assert {:ok, _} = create_capturing(:open_stable, %{title: "Stable"})
      assert_receive {:context, %{graphlaw: second}}
      assert {:ok, _} = create_capturing(:open_stable, %{title: "Different"})
      assert_receive {:context, %{graphlaw: third}}

      assert first.admission == :stable
      assert first.input_digest == second.input_digest
      assert first.digest == second.digest
      assert third.input_digest != first.input_digest
    end

    test "an untitled create is refused :not_admitted (mu_on_O) and nothing is persisted" do
      assert {:ok, _} = create_capturing(:open, %{title: "control"})
      assert [%{title: "control"}] = Ash.read!(Note)

      assert {:error, %Ash.Error.Invalid{} = error} = create_capturing(:open, %{})
      assert Error.codes(error) == violation_codes()
      assert [%{class: class, broken_term: :mu_on_O}] = Error.refusals(error)
      assert class in [:refused_admission, :refused_structure]
      assert [%{title: "control"}] = Ash.read!(Note)
    end

    test "a :construct admission without a lease is :ceiling_unmet and with a signed lease is admitted" do
      assert {:ok, _} = create_capturing(:derive, %{title: "x"}, Lease.context(:construct))

      assert {:error, error} = create_capturing(:derive, %{title: "y"})
      assert Error.codes(error) == [:ceiling_unmet]
      assert [%{class: :refused_authority, broken_term: :R_missing_authority}] = Error.refusals(error)

      assert {:error, error} = create_capturing(:derive, %{title: "z"}, Lease.context(:select))
      assert Error.codes(error) == [:ceiling_unmet]
    end
  end

  describe "Validation.Admissible" do
    test "positive control: a titled changeset is valid and persists" do
      assert {:ok, note} = Note |> Ash.Changeset.for_create(:write, %{title: "hello"}) |> Ash.create()
      assert note.title == "hello"
    end

    test "an untitled changeset is invalid with :not_admitted and nothing persists" do
      assert {:ok, _} = Note |> Ash.Changeset.for_create(:write, %{title: "control"}) |> Ash.create()
      assert [%{title: "control"}] = Ash.read!(Note)

      changeset = Ash.Changeset.for_create(Note, :write, %{})
      refute changeset.valid?
      assert Error.codes(changeset.errors) == violation_codes()
      assert {:error, %Ash.Error.Invalid{}} = Ash.create(changeset)
      assert [%{title: "control"}] = Ash.read!(Note)
    end
  end

  describe "Preparation.Admit" do
    test "generic action: an input carrying the argument runs, one without is :not_admitted" do
      assert {:ok, true} = Note |> Ash.ActionInput.for_action(:check, %{title: "ok"}) |> Ash.run_action()

      input = Ash.ActionInput.for_action(Note, :check, %{})
      refute input.valid?
      assert Error.codes(input.errors) == violation_codes()
      assert {:error, error} = Ash.run_action(input)
      assert Error.codes(error) == violation_codes()
    end

    test "read action: a query with a title reads, one without is :not_admitted and returns nothing" do
      {:ok, _} = Note |> Ash.Changeset.for_create(:seed, %{title: "seed"}) |> Ash.create()

      control = Ash.Query.for_read(Note, :checked, %{}, context: %{title: "ok"})
      assert control.valid?
      assert [%{title: "seed"}] = Ash.read!(control)

      query = Ash.Query.for_read(Note, :checked, %{})
      refute query.valid?
      assert Error.codes(query.errors) == violation_codes()
      assert {:error, error} = Ash.read(query)
      assert Error.codes(error) == violation_codes()
    end
  end

  describe "Projection.Default" do
    test "is byte-deterministic N-Triples that projects attributes and the action, and refuses foreign subjects" do
      changeset = Ash.Changeset.for_create(Note, :open, %{title: "T"})

      assert {:ok, %{text: text, dialect: "ntriples"}} = Default.data(changeset, [])
      assert {:ok, %{text: ^text}} = Default.data(changeset, [])
      assert text =~ "<urn:ash-graphlaw:attr:title>"
      assert text =~ "<urn:ash-graphlaw:action>"
      assert text =~ "\"T\"^^<http://www.w3.org/2001/XMLSchema#string>"
      assert String.ends_with?(text, "\n")

      assert {:error, %Refusal{code: :projection_failed}} = Default.data(:not_a_subject, [])
    end
  end
end
