











defmodule AshR2RML.Dsl.Class do
  @moduledoc false


  @enforce_keys [:iri]


  defstruct [
    :iri,
    :__identifier__,
    :__spark_metadata__
  ]
end

defmodule AshR2RML.Dsl.SparqlQuery do
  @moduledoc false


  @enforce_keys [:name]


  defstruct [
    :name,
    :__identifier__,
    :__spark_metadata__,
    form: :select,
    select: [],
    where: []

  ]
end

defmodule AshR2RML.Dsl.Subject do
  @moduledoc false



  defstruct [
    :template,
    :column,
    :constant,
    :__identifier__,
    :__spark_metadata__,
    term_type: :iri

  ]
end

defmodule AshR2RML.Dsl.Property do
  @moduledoc false


  @enforce_keys [:attribute, :predicate_iri]


  defstruct [
    :attribute,
    :predicate_iri,
    :datatype,
    :language,
    :language_column,
    :constant,
    :template,
    :__identifier__,
    :__spark_metadata__,
    term_type: :literal

  ]
end

defmodule AshR2RML.Dsl.Reference do
  @moduledoc false


  @enforce_keys [:relationship, :predicate_iri]


  defstruct [
    :relationship,
    :predicate_iri,
    :inverse_predicate,
    :guard_class,
    :__identifier__,
    :__spark_metadata__,
    direction: :outgoing

  ]
end

defmodule AshR2RML.Dsl.Graph do
  @moduledoc false


  @enforce_keys [:iri]


  defstruct [
    :iri,
    :__identifier__,
    :__spark_metadata__,
    scope: :resource

  ]
end



defmodule AshR2RML.Resource do
  @moduledoc """
  Spark.Dsl.Extension for `ash_r2rml`.

  Manufactured by ash-extension-core-pack from an admitted `aex:AshExtensionSpec` --
  do not hand-edit; regenerate from the spec instead.
  """








  @class %Spark.Dsl.Entity{
    name: :class,
    target: AshR2RML.Dsl.Class,

    args: [:iri],


    identifier: :iri,


    schema: [
      iri: [type: {:or, [:string, {:list, :string}]}, required: true, doc: "The RDF class IRI (or list of class IRIs) this resource maps to."],
    ]
  }




  @query %Spark.Dsl.Entity{
    name: :query,
    target: AshR2RML.Dsl.SparqlQuery,

    args: [:name],


    identifier: :name,


    schema: [
      name: [type: :atom, required: true, doc: "The query's atom name."],
      form: [type: {:one_of, [:select, :construct, :ask, :describe]}, required: false, default: :select, doc: "SPARQL query form."],
      select: [type: {:list, :atom}, required: false, default: [], doc: "Selected variables for a :select query."],
      where: [type: :any, required: false, default: [], doc: "WHERE-clause pattern data."],
    ]
  }




  @subject %Spark.Dsl.Entity{
    name: :subject,
    target: AshR2RML.Dsl.Subject,



    schema: [
      template: [type: :string, required: false, doc: "IRI template with {attr} interpolation, e.g. https://example.test/organization/{id}."],
      column: [type: :atom, required: false, doc: "Attribute whose value is used verbatim as the subject IRI/identifier."],
      constant: [type: :string, required: false, doc: "A fixed subject IRI shared by every instance."],
      term_type: [type: {:one_of, [:iri, :blank_node]}, required: false, default: :iri, doc: "Whether the subject is an :iri or a :blank_node."],
    ]
  }




  @property %Spark.Dsl.Entity{
    name: :property,
    target: AshR2RML.Dsl.Property,

    args: [:attribute, :predicate_iri],


    identifier: :attribute,


    schema: [
      attribute: [type: :atom, required: true, doc: "The Ash resource attribute this property maps."],
      predicate_iri: [type: :string, required: true, doc: "The RDF predicate IRI."],
      datatype: [type: :string, required: false, doc: "Explicit RDF literal datatype IRI, overriding the registry-resolved default."],
      language: [type: :string, required: false, doc: "Fixed BCP-47 language tag for a literal (requires term_type: :literal)."],
      language_column: [type: :atom, required: false, doc: "Attribute holding a per-row language tag."],
      constant: [type: :string, required: false, doc: "A fixed object value shared by every instance."],
      template: [type: :string, required: false, doc: "Object-value template with {attr} interpolation."],
      term_type: [type: {:one_of, [:literal, :iri, :blank_node]}, required: false, default: :literal, doc: "Whether the object is a :literal, :iri, or :blank_node."],
    ]
  }




  @reference %Spark.Dsl.Entity{
    name: :reference,
    target: AshR2RML.Dsl.Reference,

    args: [:relationship, :predicate_iri],


    identifier: :relationship,


    schema: [
      relationship: [type: :atom, required: true, doc: "The Ash relationship this reference follows."],
      predicate_iri: [type: :string, required: true, doc: "The RDF predicate IRI."],
      inverse_predicate: [type: :string, required: false, doc: "Optional inverse predicate IRI."],
      direction: [type: {:one_of, [:outgoing, :incoming]}, required: false, default: :outgoing, doc: "Whether the predicate points :outgoing or :incoming."],
      guard_class: [type: :string, required: false, doc: "Optional class IRI guard on the related resource."],
    ]
  }




  @graph %Spark.Dsl.Entity{
    name: :graph,
    target: AshR2RML.Dsl.Graph,

    args: [:iri],


    identifier: :iri,


    schema: [
      iri: [type: :string, required: true, doc: "The named graph IRI."],
      scope: [type: {:one_of, [:resource, :subject]}, required: false, default: :resource, doc: "Whether the graph scope is per-:resource or per-:subject."],
    ]
  }





  @r2rml %Spark.Dsl.Section{
    name: :r2rml,

    describe: "Semantic mapping metadata normalized into AshR2RML.Mapping",


    schema: [
      table_name: [type: :string],
      sql_query: [type: :string],
      schema: [type: :string],
    ],

    entities: [
      @class,
      @subject,
      @property,
      @reference,
      @graph,
    ],
    singleton_entity_keys: [:subject]


  }



  @sparql %Spark.Dsl.Section{
    name: :sparql,

    describe: "Declarative SPARQL query definitions compiled with the resource",


    entities: [
      @query,
    ]

  }


  use Spark.Dsl.Extension,
    sections: [@r2rml, @sparql],
    transformers: [AshR2RML.Resource.Persist],
    verifiers: [AshR2RML.Resource.Verify],
    single_extension_kinds: [:ash_r2rml]

end
