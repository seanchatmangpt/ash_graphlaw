# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): test fixtures for the Ash lifecycle modules

defmodule AshGraphLaw.Test.Lifecycle.Projection do
  @moduledoc """
  UNSUPPORTED(generator-capability): deterministic N-Triples projection over the `:title`
  attribute only.

  Unlike `AshGraphLaw.Projection.Default` the subject IRI does not contain the primary key and the
  `:graph_id` attribute is never projected, so two records with equal titles project to
  byte-identical text (and therefore to equal canonical ids).
  """

  @behaviour AshGraphLaw.Projection

  alias AshGraphLaw.Test.NTriples

  @ns "urn:ash-graphlaw:lifecycle:"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  @doc "The namespace of the projected vocabulary."
  @spec ns() :: String.t()
  def ns, do: @ns

  @impl true
  def data(%Ash.Changeset{} = changeset, _opts) do
    subject = @ns <> "note"

    title =
      case Ash.Changeset.get_attribute(changeset, :title) do
        nil -> []
        text -> [{subject, @ns <> "title", {:lit, text, @xsd_string}}]
      end

    {:ok, %{text: NTriples.render([{subject, @rdf_type, @ns <> "Note"} | title]), dialect: "ntriples"}}
  end

  def data(_other, _opts), do: {:error, AshGraphLaw.Refusal.new(:projection_failed, "only changesets are projected")}
end

defmodule AshGraphLaw.Test.Lifecycle.Domain do
  @moduledoc "UNSUPPORTED(generator-capability): Ash domain for the lifecycle test resources."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Test.Lifecycle.Note
    resource AshGraphLaw.Test.Lifecycle.CanonOnly
    resource AshGraphLaw.Test.Lifecycle.ShaclOnly
  end
end

defmodule AshGraphLaw.Test.Lifecycle.Note do
  @moduledoc """
  UNSUPPORTED(generator-capability): lifecycle reference resource. Declares no capability, so
  every typed op is allowed (back-compat).

    * `:seed` (create) has no hooks, so tests can store real records without the engine;
    * `:write` (create) validates against the SHACL shape and stores the canonical id;
    * `:rename` (update) validates against the SHACL shape;
    * `:canonicalize` (create) and `:recanonicalize` (update) only store the canonical id;
    * `:write_broken` (create) validates against a shapes graph the engine refuses.
  """

  use Ash.Resource,
    domain: AshGraphLaw.Test.Lifecycle.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  alias AshGraphLaw.Calculation.CanonicalId
  alias AshGraphLaw.Calculation.Conforms
  alias AshGraphLaw.Calculation.Sparql
  alias AshGraphLaw.Change.Canonicalize
  alias AshGraphLaw.Test.Lifecycle.Projection
  alias AshGraphLaw.Validation.Shacl

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix t: <urn:ash-graphlaw:lifecycle:> .

  t:NoteShape a sh:NodeShape ;
    sh:targetClass t:Note ;
    sh:property [
      sh:path t:title ;
      sh:minCount 1 ;
      sh:datatype xsd:string ;
      sh:minLength 1
    ] .
  """

  @broken_shapes "this is @@ not a shapes graph"

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :graph_id, :string, public?: true
  end

  actions do
    defaults [:read]

    create :seed do
      accept [:title]
    end

    create :write do
      accept [:title]
      validate {Shacl, shapes: @shapes, projection: Projection}
      change {Canonicalize, attribute: :graph_id, projection: Projection}
    end

    update :rename do
      require_atomic? false
      accept [:title]
      validate {Shacl, shapes: @shapes, projection: Projection}
    end

    create :canonicalize do
      accept [:title]
      change {Canonicalize, attribute: :graph_id, projection: Projection}
    end

    update :recanonicalize do
      require_atomic? false
      accept [:title]
      change {Canonicalize, attribute: :graph_id, projection: Projection}
    end

    create :write_broken do
      accept [:title]
      validate {Shacl, shapes: @broken_shapes, projection: Projection}
    end
  end

  calculations do
    calculate :conforms?, :boolean, {Conforms, shapes: @shapes, projection: Projection}
    calculate :broken_conforms?, :boolean, {Conforms, shapes: @broken_shapes, projection: Projection}
    calculate :canonical_id, :string, {CanonicalId, projection: Projection}
    calculate :default_canonical_id, :string, CanonicalId

    calculate :titles,
              :term,
              {Sparql, query: "SELECT ?t WHERE { ?s <urn:ash-graphlaw:lifecycle:title> ?t }", projection: Projection}

    calculate :titles_raw,
              :term,
              {Sparql,
               query: "SELECT ?t WHERE { ?s <urn:ash-graphlaw:lifecycle:title> ?t }",
               terms: :raw,
               projection: Projection}

    calculate :titled?,
              :term,
              {Sparql, query: "ASK { ?s <urn:ash-graphlaw:lifecycle:title> ?t }", projection: Projection}

    calculate :titled_graph,
              :term,
              {Sparql,
               query:
                 "CONSTRUCT { ?s <urn:ash-graphlaw:lifecycle:label> ?t } WHERE { ?s <urn:ash-graphlaw:lifecycle:title> ?t }",
               projection: Projection}

    calculate :malformed, :term, {Sparql, query: "SELECT WHERE {{{ not sparql", projection: Projection}
  end
end

defmodule AshGraphLaw.Test.Lifecycle.CanonOnly do
  @moduledoc """
  UNSUPPORTED(generator-capability): declares only `:canonical`. Every other typed op is refused
  with `:capability_not_declared` before the engine is called.
  """

  use Ash.Resource,
    domain: AshGraphLaw.Test.Lifecycle.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  alias AshGraphLaw.Calculation.CanonicalId
  alias AshGraphLaw.Calculation.Conforms
  alias AshGraphLaw.Calculation.Sparql
  alias AshGraphLaw.Test.Lifecycle.Projection
  alias AshGraphLaw.Validation.Shacl

  @shapes "@prefix sh: <http://www.w3.org/ns/shacl#> . <urn:s:S> a sh:NodeShape ."

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]

    create :seed do
      accept [:title]
    end

    create :write do
      accept [:title]
      validate {Shacl, shapes: @shapes, projection: Projection}
    end
  end

  calculations do
    calculate :canonical_id, :string, {CanonicalId, projection: Projection}
    calculate :conforms?, :boolean, {Conforms, shapes: @shapes, projection: Projection}
    calculate :titled?, :term, {Sparql, query: "ASK { ?s ?p ?o }", projection: Projection}
  end

  graphlaw do
    capability(:canonical)
  end
end

defmodule AshGraphLaw.Test.Lifecycle.ShaclOnly do
  @moduledoc """
  UNSUPPORTED(generator-capability): declares only `:shacl`, so `canonical` is refused.
  """

  use Ash.Resource,
    domain: AshGraphLaw.Test.Lifecycle.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  alias AshGraphLaw.Calculation.CanonicalId
  alias AshGraphLaw.Calculation.Conforms
  alias AshGraphLaw.Change.Canonicalize
  alias AshGraphLaw.Test.Lifecycle.Projection

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix t: <urn:ash-graphlaw:lifecycle:> .
  t:NoteShape a sh:NodeShape ; sh:targetClass t:Note ;
    sh:property [ sh:path t:title ; sh:minCount 1 ] .
  """

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :graph_id, :string, public?: true
  end

  actions do
    defaults [:read]

    create :seed do
      accept [:title]
    end

    create :canonicalize do
      accept [:title]
      change {Canonicalize, attribute: :graph_id, projection: Projection}
    end
  end

  calculations do
    calculate :conforms?, :boolean, {Conforms, shapes: @shapes, projection: Projection}
    calculate :canonical_id, :string, {CanonicalId, projection: Projection}
  end

  graphlaw do
    capability(:shacl)
  end
end
