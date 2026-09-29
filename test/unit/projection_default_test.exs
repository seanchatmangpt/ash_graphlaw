# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Projection.DefaultTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Projection.Default
  alias AshGraphLaw.Test.Account
  alias AshGraphLaw.Test.Ticket

  @secret "hunter2-correct-horse"

  defp create_changeset(title) do
    Ash.Changeset.for_create(Ticket, :open, %{title: title})
  end

  defp lines(text), do: String.split(text, "\n", trim: true)

  describe "positive control" do
    test "projects a create changeset to non-empty N-Triples naming the resource and the title" do
      assert {:ok, %{text: text, dialect: "ntriples"}} = Default.data(create_changeset("plain title"), [])

      assert text =~ "<urn:ash-graphlaw:resource:AshGraphLaw.Test.Ticket:"
      assert text =~ "plain title"
    end

    test "every emitted line is a complete N-Triples statement ending in ' .'" do
      {:ok, %{text: text}} = Default.data(create_changeset("plain title"), [])

      assert lines(text) != []
      assert Enum.all?(lines(text), &String.ends_with?(&1, " ."))
      assert Enum.all?(lines(text), &String.starts_with?(&1, "<"))
    end

    test "the action name and type are part of the projection" do
      {:ok, %{text: text}} = Default.data(create_changeset("t"), [])

      assert text =~ "open"
      assert text =~ "create"
    end
  end

  describe "determinism" do
    test "the same changeset projects to byte-identical text every time" do
      changeset = create_changeset("stable")
      {:ok, a} = Default.data(changeset, [])
      {:ok, b} = Default.data(changeset, [])
      {:ok, c} = Default.data(changeset, [])

      assert a.text == b.text
      assert b.text == c.text
    end

    test "statements are sorted and unique" do
      {:ok, %{text: text}} = Default.data(create_changeset("sorted"), [])
      statements = lines(text)

      assert statements == Enum.sort(statements)
      assert statements == Enum.uniq(statements)
    end

    test "the projection depends on the input: a different title yields different text" do
      {:ok, a} = Default.data(Ash.Changeset.for_create(Ticket, :seed, %{title: "alpha"}), [])
      {:ok, b} = Default.data(Ash.Changeset.for_create(Ticket, :seed, %{title: "beta"}), [])

      assert a.text =~ "alpha"
      assert b.text =~ "beta"
      refute a.text =~ "beta"
      refute a.text == b.text
    end
  end

  describe "update changesets" do
    test "the subject IRI is keyed on the stored record's primary key" do
      record = Ash.create!(Ash.Changeset.for_create(Ticket, :seed, %{title: "stored"}))
      changeset = Ash.Changeset.for_update(record, :close, %{})

      assert {:ok, %{text: text}} = Default.data(changeset, [])
      assert text =~ "<urn:ash-graphlaw:resource:AshGraphLaw.Test.Ticket:#{record.id}>"
      assert text =~ "close"
      assert text =~ "update"
    end
  end

  describe "query subjects" do
    test "a read query projects deterministically with the action name" do
      query = Ash.Query.for_read(Ticket, :read)

      assert {:ok, %{text: a, dialect: "ntriples"}} = Default.data(query, [])
      assert {:ok, %{text: b}} = Default.data(query, [])
      assert a == b
      assert a =~ "read"
    end
  end

  describe "escaping" do
    @nasty "quote \" backslash \\ newline \n tab \t carriage \r end"

    test "positive control: the same shape with benign text has no escapes" do
      {:ok, %{text: text}} = Default.data(create_changeset("benign text"), [])
      refute text =~ "\\"
    end

    test "quotes, backslashes and control characters are escaped per N-Triples" do
      {:ok, %{text: text}} = Default.data(create_changeset(@nasty), [])

      assert text =~ ~S(quote \" backslash \\ newline)
      assert text =~ ~S(\n tab)
      assert text =~ ~S(\t carriage)
      assert text =~ ~S(\r end)
    end

    test "escaped literals never introduce a raw line break: every line is a whole statement" do
      {:ok, %{text: text}} = Default.data(create_changeset(@nasty), [])

      refute text =~ "\r"
      assert Enum.all?(lines(text), &String.ends_with?(&1, " ."))
    end

    test "non-ASCII text is preserved as valid UTF-8" do
      {:ok, %{text: text}} = Default.data(create_changeset("café ☃"), [])
      assert String.valid?(text)
      assert text =~ "caf" and (text =~ "é" or text =~ "\\u00E9" or text =~ "\\u00e9")
    end
  end

  describe "sensitive redaction" do
    test "positive control: a non-sensitive attribute of the same changeset IS projected" do
      changeset = Ash.Changeset.for_create(Account, :register, %{name: "visible-name", password: @secret})
      {:ok, %{text: text}} = Default.data(changeset, [])

      assert text =~ "visible-name"
    end

    test "a sensitive attribute value never appears in the projection" do
      changeset = Ash.Changeset.for_create(Account, :register, %{name: "visible-name", password: @secret})
      {:ok, %{text: text}} = Default.data(changeset, [])

      refute text =~ @secret
    end
  end

  describe "real parse (needs the real wasm engine)" do
    @describetag :wasm

    test "the engine parses the projection of a nasty-text changeset as valid N-Triples" do
      host = AshGraphLaw.Test.Case.start_host!()
      {:ok, %{text: text}} = Default.data(create_changeset(@nasty), [])

      assert {:ok, %{"ok" => true, "dialect" => "NTriples", "quads" => quads}} =
               AshGraphLaw.Host.request(host, %{"op" => "parse", "text" => text, "dialect" => "ntriples"})

      assert quads >= 1
    end
  end
end
