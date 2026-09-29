# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.ShapeLaw do
  @moduledoc """
  UNSUPPORTED(generator-capability): a real `AshGraphLaw.Law` whose single step is a SHACL
  shape in the GraphLaw `law` op format (`{"step": "shacl", "shapes": <turtle>}`).

  The shape requires every `Ticket` to carry a `title` that is an `xsd:string` of length >= 1.
  `data/2` projects the changeset into that vocabulary itself (rather than relying on the
  default projection's vocabulary), so the shape is decided against real, replayable data.
  """

  @behaviour AshGraphLaw.Law

  alias AshGraphLaw.Test.NTriples

  @ns "urn:ash-graphlaw:test:"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix t: <#{@ns}> .

  t:TicketShape a sh:NodeShape ;
    sh:targetClass t:Ticket ;
    sh:property [
      sh:path t:title ;
      sh:minCount 1 ;
      sh:datatype xsd:string ;
      sh:minLength 1
    ] .
  """

  @doc "The SHACL shapes document (Turtle) this law submits."
  @spec shapes() :: String.t()
  def shapes, do: @shapes

  @impl true
  def steps(_subject, _admission), do: [%{"step" => "shacl", "shapes" => @shapes}]

  @impl true
  def data(%Ash.Changeset{} = changeset, _admission) do
    id = changeset.data |> Map.get(:id) |> Kernel.||("new")
    subject = "#{@ns}ticket:#{id}"

    type = {subject, @rdf_type, "#{@ns}Ticket"}

    title =
      case Ash.Changeset.get_attribute(changeset, :title) do
        nil -> []
        text -> [{subject, "#{@ns}title", {:lit, text, @xsd_string}}]
      end

    {:ok, %{text: NTriples.render([type | title]), dialect: "ntriples"}}
  end

  def data(_subject, _admission), do: :default
end
