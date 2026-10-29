
defmodule NotificationExtension.Resource.Reactor.Steps.Admit do
  @moduledoc """
  Reactor step `:admit` (order 1) of `notification_extension`'s
  declared pipeline. Generated from its `aex:ReactorStep` row -- regenerate, do not
  hand-edit.
  """
  use Reactor.Step

  @impl true
  def run(arguments, _context, _options) do
    {:ok, %{step: :admit, arguments: arguments}}
  end
end
