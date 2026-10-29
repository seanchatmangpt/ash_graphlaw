











defmodule AuditTrail.Dsl.Event do
  @moduledoc false



  defstruct [
    :name,
    :description,
    :__identifier__,
    :__spark_metadata__
  ]
end

defmodule AuditTrail.Dsl.Projection do
  @moduledoc false



  defstruct [
    :attribute,
    :__identifier__,
    :__spark_metadata__
  ]
end



defmodule AuditTrail.Resource do
  @moduledoc """
  Spark.Dsl.Extension for `audit_trail`.

  Manufactured by ash-extension-core-pack from an admitted `aex:AshExtensionSpec` --
  do not hand-edit; regenerate from the spec instead.
  """








  @event %Spark.Dsl.Entity{
    name: :event,
    target: AuditTrail.Dsl.Event,



    schema: [
      name: [type: :atom, required: true, doc: "The audited event's slug."],
      description: [type: :string, required: false, doc: "Human-readable description of what triggers this event."],
    ]
  }




  @projection %Spark.Dsl.Entity{
    name: :projection,
    target: AuditTrail.Dsl.Projection,



    schema: [
      attribute: [type: :atom, required: true, doc: "Resource attribute this projection reads."],
    ]
  }





  @audit %Spark.Dsl.Section{
    name: :audit,


    entities: [
      @event,
      @projection,
    ]

  }


  use Spark.Dsl.Extension,
    sections: [@audit],
    transformers: [AuditTrail.Resource.Persist],
    verifiers: [AuditTrail.Resource.Verify]

end
