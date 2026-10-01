defmodule AshGraphLaw.Dsl.Runtime do
  @moduledoc false

  defstruct [
    :wasm_path,
    :__identifier__,
    :__spark_metadata__,
    timeout_ms: 5000,
    max_skew_secs: 60,
    trusted_keys: []
  ]
end

defmodule AshGraphLaw.Dsl.Admission do
  @moduledoc false

  @enforce_keys [:name]

  defstruct [
    :name,
    :step,
    :law,
    :projection,
    :__identifier__,
    :__spark_metadata__,
    ceiling: :construct
  ]
end

defmodule AshGraphLaw.Dsl.Capability do
  @moduledoc false

  @enforce_keys [:name]

  defstruct [
    :name,
    :doc,
    :__identifier__,
    :__spark_metadata__,
    ceiling: :observe
  ]
end

defmodule AshGraphLaw.Resource do
  @moduledoc """
  Spark.Dsl.Extension for `ash_graphlaw`.

  Manufactured by ash-extension-core-pack from an admitted `aex:AshExtensionSpec` --
  do not hand-edit; regenerate from the spec instead.
  """

  @runtime %Spark.Dsl.Entity{
    name: :runtime,
    target: AshGraphLaw.Dsl.Runtime,
    schema: [
      wasm_path: [
        type: :string,
        required: false,
        doc:
          "Path to a graphlaw.wasm file. Nil uses the resolution order in AshGraphLaw.WasmConfig; the digest pin still applies to the vendored path."
      ],
      timeout_ms: [
        type: :integer,
        required: false,
        default: 5000,
        doc: "Per-call timeout in milliseconds. Must be positive."
      ],
      max_skew_secs: [
        type: :integer,
        required: false,
        default: 60,
        doc: "Allowed clock skew in seconds when the engine checks a lease. Must not be negative."
      ],
      trusted_keys: [
        type: {:list, :string},
        required: false,
        default: [],
        doc: "Hex-encoded 32-byte public keys (64 characters each) whose lease signatures the engine may accept."
      ]
    ]
  }

  @admission %Spark.Dsl.Entity{
    name: :admission,
    target: AshGraphLaw.Dsl.Admission,
    args: [:name],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "Unique name of the admission within the resource."],
      step: [
        type: {:one_of, [:shacl, :n3, :rdfs, :owl_rl, :hooks, :plan, :require_receipt, :require_signed_receipt]},
        required: true,
        doc: "The GraphLaw law step this admission runs."
      ],
      ceiling: [
        type: {:one_of, [:observe, :select, :construct]},
        required: false,
        default: :construct,
        doc:
          "Highest authority ceiling the caller's lease must reach before the engine is consulted. Admission itself never grants authority."
      ],
      law: [
        type: :module,
        required: false,
        doc: "Module implementing AshGraphLaw.Law that supplies the step payload for this admission."
      ],
      projection: [
        type: :module,
        required: false,
        doc:
          "Module implementing AshGraphLaw.Projection that turns the subject into RDF data. Nil uses AshGraphLaw.Projection.Default."
      ]
    ]
  }

  @capability %Spark.Dsl.Entity{
    name: :capability,
    target: AshGraphLaw.Dsl.Capability,
    args: [:name],
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc:
          "Registry op name this resource declares (for example :sparql or :shacl). Must be a name in AshGraphLaw.Capability.Registry.names/0."
      ],
      ceiling: [
        type: {:one_of, [:observe, :select, :construct]},
        required: false,
        default: :observe,
        doc:
          "Authority ceiling declared for this capability. Must not be below the ceiling the op needs (observe for read-only ops, construct for n3, entail, datalog, hooks, law). Declaring a ceiling never grants authority."
      ],
      doc: [type: :string, required: false, doc: "Free-text note on why the resource declares this capability."]
    ]
  }

  @graphlaw %Spark.Dsl.Section{
    name: :graphlaw,
    describe: "GraphLaw admission configuration: one runtime entity and any number of named admissions.",
    entities: [
      @runtime,
      @admission,
      @capability
    ],
    singleton_entity_keys: [:runtime]
  }

  use Spark.Dsl.Extension,
    sections: [@graphlaw],
    transformers: [AshGraphLaw.Resource.Persist],
    verifiers: [AshGraphLaw.Resource.Verify],
    single_extension_kinds: [:ash_graphlaw]
end
