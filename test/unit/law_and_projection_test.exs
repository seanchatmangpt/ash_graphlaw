# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.LawAndProjectionTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test over real modules and a real changeset.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.CheatSheet
  alias AshGraphLaw.Law
  alias AshGraphLaw.Projection
  alias AshGraphLaw.Test.{ShapeLaw, Ticket}

  defp changeset(title \\ "a title"), do: Ash.Changeset.for_create(Ticket, :seed, %{title: title})
  defp admission, do: elem(Admissions.fetch(Ticket, :ticket_shape), 1)

  describe "Law.data/3" do
    test "positive control: a law module that exports data/2 supplies the data" do
      assert {:ok, %{text: text, dialect: "ntriples"}} = Law.data(ShapeLaw, changeset(), admission())
      assert text =~ "a title"
    end

    test "a module without data/2, and a module that does not exist, select the default projection" do
      assert Law.data(Enum, changeset(), admission()) == :default
      assert Law.data(AshGraphLaw.Test.NoSuchLaw, changeset(), admission()) == :default
    end
  end

  describe "Projection.input_digest/1" do
    test "positive control: the digest is the sha256 of the projected text, and changes with it" do
      a = %{text: "<urn:a> <urn:p> <urn:b> .\n", dialect: "ntriples"}
      b = %{text: "<urn:a> <urn:p> <urn:c> .\n", dialect: "ntriples"}

      assert Projection.input_digest(a) == :sha256 |> :crypto.hash(a.text) |> Base.encode16(case: :lower)
      assert Projection.input_digest(a) == Projection.input_digest(a)
      refute Projection.input_digest(a) == Projection.input_digest(b)
    end

    test "data without text has no digest" do
      no_text = Map.new([{:dialect, "ntriples"}])
      assert_raise FunctionClauseError, fn -> Projection.input_digest(no_text) end
    end
  end

  describe "CheatSheet.generate/0" do
    test "renders the compiled extension's DSL from Spark" do
      sheet = CheatSheet.generate()
      assert sheet =~ "graphlaw.runtime"
      assert sheet =~ "graphlaw.admission"
      assert sheet =~ "trusted_keys"
    end
  end
end
