# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.PlanLaw do
  @moduledoc """
  UNSUPPORTED(generator-capability): a real `AshGraphLaw.Law` whose single step is a plan in
  the GraphLaw `law` op format (`{"step": "plan", "plan": {actions, goal}}`).

  The plan has one action, `close`: precondition "ticket state is open", add "ticket state is
  closed", delete "ticket state is open"; goal "ticket state is closed". `data/2` projects the
  ticket's CURRENT (stored) state, so closing an already-closed ticket is refused by the
  engine as a `PlanRefused` at step 0 -- the precondition is really checked, not assumed.
  """

  @behaviour AshGraphLaw.Law

  alias AshGraphLaw.Test.NTriples

  @ns "urn:ash-graphlaw:test:"

  @impl true
  def steps(subject, _admission) do
    id = ticket_id(subject)

    [
      %{
        "step" => "plan",
        "plan" => %{
          "actions" => [
            %{
              "name" => "close",
              "pre" => state(id, :open),
              "add" => state(id, :closed),
              "del" => state(id, :open)
            }
          ],
          "goal" => state(id, :closed)
        }
      }
    ]
  end

  @impl true
  def data(%Ash.Changeset{data: %{state: current}} = changeset, _admission) do
    {:ok, %{text: state(ticket_id(changeset), current), dialect: "ntriples"}}
  end

  def data(_subject, _admission), do: :default

  defp ticket_id(%Ash.Changeset{data: data}), do: Map.get(data, :id) || "new"

  defp state(id, value) do
    NTriples.render([{"#{@ns}ticket:#{id}", "#{@ns}state", "#{@ns}#{value}"}])
  end
end
