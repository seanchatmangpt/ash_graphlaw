
defmodule NotificationExtension.Resource.Reactor.Steps.SealReceipt do
  @moduledoc """
  Reactor step `:seal_receipt` (order 3) of `notification_extension`'s
  declared pipeline. Generated from its `aex:ReactorStep` row -- regenerate, do not
  hand-edit.
  """
  use Reactor.Step

  @impl true
  def run(arguments, _context, _options) do
    {:ok, %{step: :seal_receipt, arguments: arguments}}
  end
end
