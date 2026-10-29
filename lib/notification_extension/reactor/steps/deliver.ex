
defmodule NotificationExtension.Resource.Reactor.Steps.Deliver do
  @moduledoc """
  Reactor step `:deliver` (order 2) of `notification_extension`'s
  declared pipeline. Generated from its `aex:ReactorStep` row -- regenerate, do not
  hand-edit.
  """
  use Reactor.Step

  @impl true
  def run(arguments, _context, _options) do
    {:ok, %{step: :deliver, arguments: arguments}}
  end

  @impl true
  def compensate(_reason, _arguments, _context, _options), do: :ok
end
