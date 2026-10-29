



defmodule NotificationExtension.Resource.Info do
  @moduledoc """
  Public introspection API for `notification_extension`.
  """

  @doc "Returns the raw `:notification` DSL entities declared on `resource`."
  def notification(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:notification])
  end

  @doc "Returns the transformer-normalized compiled state for `resource`, or `nil` if the extension is not present."
  def compiled(resource) do
    case compiled_result(resource) do
      {:ok, compiled} -> compiled
      {:error, _} -> nil
    end
  end

  @doc """
  Returns `{:ok, compiled}` or `{:error, :not_compiled}` for `resource`.

  """
  def compiled_result(resource) do
    case Spark.Dsl.Extension.get_persisted(resource, :notification_extension_compiled, nil) do
      nil -> {:error, :not_compiled}
      compiled -> {:ok, compiled}
    end

  end

  @doc "Bang variant of `compiled_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def compiled!(resource) do
    case compiled_result(resource) do
      {:ok, compiled} -> compiled
      {:error, reason} -> raise ArgumentError, "NotificationExtension.Resource.Info.compiled!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry compiled `notification_extension` state?"
  def compiled?(resource) do
    match?({:ok, _}, compiled_result(resource))
  end

  @doc "Returns the `:notification`-derived `channel_index`, or `nil` if `resource` has no compiled `notification_extension` state."
  def channel_index(resource) do
    case channel_index_result(resource) do
      {:ok, value} -> value
      {:error, :not_found} -> nil
    end
  end

  @doc "Returns `{:ok, channel_index}` or `{:error, :not_found}` for `resource`'s `:notification` section."
  def channel_index_result(resource) do
    case compiled_result(resource) do
      {:ok, %{ notification: value} } -> {:ok, value}
      {:ok, _compiled} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc "Bang variant of `channel_index_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def channel_index!(resource) do
    case channel_index_result(resource) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "NotificationExtension.Resource.Info.channel_index!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry a `channel_index`?"
  def channel_index?(resource) do
    match?({:ok, _}, channel_index_result(resource))
  end

end
