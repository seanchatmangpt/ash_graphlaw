# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.ProjectionTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite; real Ash changesets on a real resource.
  use AshGraphLaw.Test.PropertyCase, async: true

  alias AshGraphLaw.Projection.Default
  alias AshGraphLaw.Test.Ticket

  @title_pred "<urn:ash-graphlaw:attr:title>"
  @iri ~S/<[^<>\s"\\]+>/
  @literal ~S/"(?:[\x20\x21\x23-\x5B\x5D-\x7E]|\\[\\"nrt]|\\u[0-9A-F]{4}|\\U[0-9A-F]{8})*"/
  @statement Regex.compile!("\\A#{@iri} #{@iri} (?:#{@iri}|#{@literal}(?:\\^\\^#{@iri})?) \\.\\z")

  defp changeset(title), do: Ash.Changeset.for_create(Ticket, :open, %{title: title})
  defp lines(text), do: String.split(text, "\n", trim: true)
  defp project!(subject), do: subject |> Default.data([]) |> then(fn {:ok, %{text: text}} -> text end)

  # Decodes one escaped N-Triples literal body back to text.
  defp unescape(body) do
    Regex.replace(~r/\\(?:([\\"nrt])|u([0-9A-F]{4})|U([0-9A-F]{8}))/, body, fn
      _, simple, "", "" -> Map.fetch!(%{"\\" => "\\", "\"" => "\"", "n" => "\n", "r" => "\r", "t" => "\t"}, simple)
      _, "", u4, "" -> <<String.to_integer(u4, 16)::utf8>>
      _, "", "", u8 -> <<String.to_integer(u8, 16)::utf8>>
    end)
  end

  defp title_literal(text) do
    text
    |> lines()
    |> Enum.find_value(fn line ->
      case Regex.run(~r/\A<[^>]+> #{Regex.escape(@title_pred)} "(.*)"\^\^<[^>]+> \.\z/, line) do
        [_, body] -> body
        nil -> nil
      end
    end)
  end

  describe "positive controls" do
    test "a plain title projects to valid N-Triples that decode back to the title" do
      text = project!(changeset("plain title"))

      assert text =~ "urn:ash-graphlaw:resource:AshGraphLaw.Test.Ticket"
      assert Enum.all?(lines(text), &Regex.match?(@statement, &1))
      assert text |> title_literal() |> unescape() == "plain title"
    end
  end

  describe "Projection.Default over arbitrary attribute text" do
    property "output is deterministic, sorted and unique" do
      check all(title <- text(), max_runs: max_runs()) do
        first = project!(changeset(title))
        assert first == project!(changeset(title))

        ls = lines(first)
        assert ls == Enum.sort(ls)
        assert ls == Enum.uniq(ls)
      end
    end

    property "attribute-map insertion order and key type do not change the output" do
      check all(
              title <- text(),
              state <- member_of([:open, :closed]),
              flip <- boolean(),
              max_runs: max_runs()
            ) do
        pairs = [title: title, state: state]
        ordered = if flip, do: Enum.reverse(pairs), else: pairs

        atom_params = Map.new(ordered)
        string_params = Map.new(ordered, fn {k, v} -> {Atom.to_string(k), v} end)

        build = fn params -> Ash.Changeset.for_create(Ticket, :seed, params) end
        assert project!(build.(atom_params)) == project!(build.(string_params))
        assert project!(build.(atom_params)) == project!(build.(Map.new(Enum.reverse(ordered))))
      end
    end

    property "every line is a well-formed ASCII N-Triples statement (no injection)" do
      check all(title <- text(), max_runs: max_runs()) do
        text = project!(changeset(title))

        assert String.ends_with?(text, "\n") or text == ""
        assert String.printable?(text) or text == ""
        assert text |> String.to_charlist() |> Enum.all?(&(&1 in 0x20..0x7E or &1 == ?\n))

        for line <- lines(text) do
          assert Regex.match?(@statement, line), "malformed line: #{inspect(line)}"
        end
      end
    end

    property "the title literal decodes back to exactly the cast attribute value" do
      check all(title <- text(), max_runs: max_runs()) do
        cs = changeset(title)
        text = project!(cs)

        case Ash.Changeset.get_attribute(cs, :title) do
          nil -> assert title_literal(text) == nil
          cast -> assert text |> title_literal() |> unescape() == cast
        end
      end
    end

    property "hostile text cannot add statements: line count depends only on populated slots" do
      check all(title <- text(), max_runs: max_runs()) do
        cs = changeset(title)
        populated = if Ash.Changeset.get_attribute(cs, :title) in [nil], do: 0, else: 1
        baseline = changeset("x") |> project!() |> lines() |> length()
        assert cs |> project!() |> lines() |> length() == baseline - 1 + populated
      end
    end

    property "distinct cast titles project to distinct text" do
      check all(a <- text(), b <- text(), max_runs: max_runs()) do
        ca = Ash.Changeset.get_attribute(changeset(a), :title)
        cb = Ash.Changeset.get_attribute(changeset(b), :title)

        if ca != cb do
          refute project!(changeset(a)) == project!(changeset(b))
        end
      end
    end
  end

  describe "unsupported subjects" do
    property "anything that is not a changeset, query or action input is :projection_failed" do
      check all(subject <- foreign_subject(), max_runs: max_runs()) do
        assert {:error, %Refusal{code: :projection_failed, class: :refused_structure}} = Default.data(subject, [])
      end
    end
  end
end
