











defmodule NotificationExtension.Dsl.Channel do
  @moduledoc false



  defstruct [
    :name,
    :__identifier__,
    :__spark_metadata__
  ]
end



defmodule NotificationExtension.Resource do
  @moduledoc """
  Spark.Dsl.Extension for `notification_extension`.

  Manufactured by ash-extension-core-pack from an admitted `aex:AshExtensionSpec` --
  do not hand-edit; regenerate from the spec instead.
  """








  @channel %Spark.Dsl.Entity{
    name: :channel,
    target: NotificationExtension.Dsl.Channel,



    schema: [
      name: [type: :atom, required: true, doc: "The notification channel's slug."],
    ]
  }





  @notification %Spark.Dsl.Section{
    name: :notification,

    describe: "Notification channel and delivery-rule metadata.",


    entities: [
      @channel,
    ]

  }


  use Spark.Dsl.Extension,
    sections: [@notification],
    transformers: [NotificationExtension.Resource.Persist],
    verifiers: [NotificationExtension.Resource.Verify]

end
