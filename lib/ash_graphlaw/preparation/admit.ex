# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Preparation.Admit do
  @moduledoc """
  Ash preparation that runs a declared GraphLaw admission at prepare time.

  UNSUPPORTED(generator-capability): hand-written; Ash preparations are outside every listed pack.

  Supports `Ash.Query` and `Ash.ActionInput`. Options are the same as
  `AshGraphLaw.Validation.Admissible` (`admission`, `projection`, `server`, `timeout`,
  `lease_key`). On refusal the subject receives an `AshGraphLaw.Error.Refused` error carrying the
  typed `AshGraphLaw.Refusal`. GraphLaw derives and validates; it never authorizes.
  """

  use Ash.Resource.Preparation

  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Validation.Admissible

  @doc false
  @impl Ash.Resource.Preparation
  def init(opts), do: Admissible.init(opts)

  @doc false
  @impl Ash.Resource.Preparation
  def supports(_opts), do: [Ash.Query, Ash.ActionInput]

  @doc false
  @impl Ash.Resource.Preparation
  def prepare(subject, opts, _context) do
    case Admissible.admit(subject, opts) do
      :ok -> subject
      {:error, refusal} -> add_error(subject, Refused.exception(refusal: refusal))
    end
  end

  defp add_error(%Ash.Query{} = query, error), do: Ash.Query.add_error(query, error)
  defp add_error(%Ash.ActionInput{} = input, error), do: Ash.ActionInput.add_error(input, error)
end
