# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits negative courts.

defmodule AshGraphLaw.Negative.ProjectionNegativeTest do
  @moduledoc """
  Negative court for the default N-Triples projection.

  A `sensitive?: true` attribute must never appear in projected text, and attacker-shaped
  attribute values (quotes, newlines, `> .`, backslashes, control characters) must not be
  able to end a literal and forge an extra triple. Well-formedness is checked line by line
  against a strict N-Triples grammar, and (under `:wasm`) by the real engine's parser, whose
  quad count must equal the number of projected lines.
  """

  use AshGraphLaw.Test.Case, async: true

  alias AshGraphLaw.Projection.Default
  alias AshGraphLaw.Test.Account

  @strict_line ~r/\A<[^<>\s"\\]+> <[^<>\s"\\]+> ("(?:[^"\\\n\r]|\\[tnr"\\]|\\u[0-9A-F]{4}|\\U[0-9A-F]{8})*"(\^\^<[^<>\s"\\]+>)?|<[^<>\s"\\]+>) \.\z/

  defp project(name, password \\ "pw") do
    changeset = Ash.Changeset.for_create(Account, :register, %{name: name, password: password})
    assert {:ok, %{text: text, dialect: "ntriples"}} = Default.data(changeset, [])
    text
  end

  defp lines(text), do: String.split(text, "\n", trim: true)

  describe "sensitive attributes" do
    test "positive control: the non-sensitive attribute is projected" do
      text = project("visible-name", "hunter2-secret")
      assert text =~ "visible-name"
    end

    test "the sensitive value never appears, raw or in any escaped rendering" do
      secret = "hunter2-SECRET-\"quoted\"\nline"
      text = project("someone", secret)

      refute text =~ "hunter2"
      refute text =~ "SECRET"
      refute text =~ "attr:password"
      refute text =~ Base.encode64(secret)
      refute text =~ URI.encode(secret)
    end

    test "changing only the sensitive value does not change the projection" do
      assert project("same", "one") == project("same", "two")
    end

    test "changing the non-sensitive value does change it (the check is not vacuous)" do
      refute project("alpha") == project("beta")
    end
  end

  describe "sensitive arguments" do
    defp project_arguments(note, token) do
      changeset =
        Ash.Changeset.for_create(Account, :register_with_arguments, %{name: "n", note: note, api_token: token})

      assert {:ok, %{text: text}} = Default.data(changeset, [])
      text
    end

    test "positive control: a non-sensitive argument IS projected" do
      assert project_arguments("visible-note", "tok-secret") =~ "visible-note"
    end

    test "a sensitive argument value and slot never appear in the projection" do
      text = project_arguments("visible-note", "tok-SECRET-9f2c")

      refute text =~ "tok-SECRET"
      refute text =~ "api_token"
      refute text =~ Base.encode64("tok-SECRET-9f2c")
    end

    test "changing only the sensitive argument leaves the projection identical; changing the note does not" do
      assert project_arguments("same", "one") == project_arguments("same", "two")
      refute project_arguments("alpha", "x") == project_arguments("beta", "x")
    end
  end

  describe "injection through attribute values" do
    @attacks [
      ~s(x" .\n<urn:forged:s> <urn:forged:p> "1" .\n),
      ~s(x"^^<http://www.w3.org/2001/XMLSchema#string> .\n<urn:forged:s> <urn:forged:p> <urn:forged:o> .),
      "x> .\r\n<urn:forged:s> <urn:forged:p> \"1\" .",
      "trailing backslash \\",
      "\\\" . <urn:forged:s> <urn:forged:p> \"1\"",
      "line1\nline2\rline3\ttab",
      "nul\0byte and \u2028 line separator and \u0085 next line",
      "emoji \u{1F600} and \u00E9 and \u{10FFFF}",
      String.duplicate("\"", 50),
      "> . <urn:forged:s> <urn:forged:p> \"1\" ."
    ]

    test "positive control: a benign value yields a fixed, well-formed line set" do
      benign = project("benign") |> lines()
      assert benign != []
      assert Enum.all?(benign, &Regex.match?(@strict_line, &1)), inspect(benign)
    end

    test "no attack adds a line, forges a subject, or breaks the grammar" do
      expected = length(lines(project("benign")))

      for attack <- @attacks do
        text = project(attack)
        ls = lines(text)

        assert length(ls) == expected, "attack changed the line count: #{inspect(attack)}"
        assert Enum.all?(ls, &Regex.match?(@strict_line, &1)), "malformed line for #{inspect(attack)}: #{inspect(ls)}"
        refute Enum.any?(ls, &String.starts_with?(&1, "<urn:forged")), "forged subject for #{inspect(attack)}"
        assert ls == Enum.sort(ls) and ls == Enum.uniq(ls)
        refute String.contains?(text, <<0>>)
      end
    end

    test "the attack text is carried only inside one literal of the subject's own triple" do
      text = project(~s(x" .\n<urn:forged:s> <urn:forged:p> "1" .\n))
      [name_line] = text |> lines() |> Enum.filter(&String.contains?(&1, "attr:name"))

      assert name_line =~ ~s(\\" .\\n<urn:forged:s>)
      assert String.starts_with?(name_line, "<urn:ash-graphlaw:resource:")
    end

    @tag :wasm
    test "the real engine's parser sees exactly one quad per projected line" do
      # positive control: the engine parses a benign projection
      host = start_host!(name: nil)
      benign = project("benign")

      assert {:ok, %{"quads" => quads}} =
               AshGraphLaw.call(%{"op" => "parse", "text" => benign, "dialect" => "ntriples"}, server: host)

      assert quads == length(lines(benign))

      for attack <- @attacks do
        text = project(attack)

        assert {:ok, %{"quads" => quads}} =
                 AshGraphLaw.call(%{"op" => "parse", "text" => text, "dialect" => "ntriples"}, server: host)

        assert quads == length(lines(text)), "engine quad count differs for #{inspect(attack)}"
      end
    end
  end
end
