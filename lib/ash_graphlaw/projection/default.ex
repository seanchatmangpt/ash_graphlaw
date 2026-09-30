# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Projection.Default do
  @moduledoc """
  Default deterministic N-Triples projection.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits it.

  Subject IRI: `<urn:ash-graphlaw:resource:{Module}:{pk-or-new}>`. Emitted triples:

    * `ag:action` and `ag:actionType` for the subject's action;
    * one `ag:attr:{name}` triple per non-nil attribute value (changesets only);
    * one `ag:arg:{name}` triple per non-nil action argument;
    * for atoms, an additional `ag:atom` marker triple naming the `attr:`/`arg:` slot;
    * for queries, `ag:query:filter`, `ag:query:sort`, `ag:query:limit`, `ag:query:offset` summaries.

  Literals are typed (`xsd:string`, `xsd:integer`, `xsd:boolean`, `xsd:dateTime`, `xsd:date`,
  `xsd:decimal`, `xsd:double`). Attributes and arguments marked `sensitive?: true` are never
  projected (redaction by omission). Lines are de-duplicated and sorted lexicographically, so the
  same input always yields byte-identical text. `\\`, `"`, newline, carriage return and tab are
  escaped; other control characters and all non-ASCII code points use UCHAR escapes.
  """

  @behaviour AshGraphLaw.Projection

  alias AshGraphLaw.Projection.Origin
  alias AshGraphLaw.Refusal

  @ag "urn:ash-graphlaw:"
  @xsd "http://www.w3.org/2001/XMLSchema#"

  @doc """
  Projects a changeset, query or action input into deterministic N-Triples.

  Returns `{:ok, %{text: text, dialect: "ntriples"}}`, or
  `{:error, %AshGraphLaw.Refusal{code: :projection_failed}}` for any other subject type
  (or an action input without a resource). `opts` is accepted for behaviour compatibility and
  ignored. Sensitive attributes and arguments are omitted, never redacted in place.
  """
  @impl true
  @spec data(AshGraphLaw.Projection.subject() | term(), keyword()) ::
          {:ok, AshGraphLaw.Projection.data()} | {:error, Refusal.t()}
  def data(subject, opts \\ [])

  def data(%Ash.Changeset{} = changeset, _opts) do
    resource = changeset.resource
    iri = subject_iri(resource, pk_segment(resource, changeset.data))

    slots =
      resource
      |> Ash.Resource.Info.attributes()
      |> Enum.reject(& &1.sensitive?)
      |> Enum.map(&{"attr:#{&1.name}", Ash.Changeset.get_attribute(changeset, &1.name)})

    lines =
      action_lines(iri, changeset.action) ++
        slot_lines(iri, slots) ++
        slot_lines(iri, argument_slots(changeset.action, changeset.arguments))

    render(lines)
  end

  def data(%Ash.Query{} = query, _opts) do
    iri = subject_iri(query.resource, "query")

    query_slots = [
      {"query:filter", if(query.filter, do: inspect(query.filter, limit: :infinity))},
      {"query:sort", if(query.sort not in [nil, []], do: inspect(query.sort, limit: :infinity))},
      {"query:limit", query.limit},
      {"query:offset", if(query.offset in [nil, 0], do: nil, else: query.offset)}
    ]

    lines =
      action_lines(iri, query.action) ++
        slot_lines(iri, query_slots) ++
        slot_lines(iri, argument_slots(query.action, query.arguments))

    render(lines)
  end

  def data(%Ash.ActionInput{resource: resource} = input, _opts) when is_atom(resource) and not is_nil(resource) do
    iri = subject_iri(resource, "input")
    render(action_lines(iri, input.action) ++ slot_lines(iri, argument_slots(input.action, input.arguments)))
  end

  def data(other, _opts) do
    {:error,
     Refusal.new(:projection_failed, "cannot project subject of type #{inspect(subject_kind(other))}", %{
       subject: subject_kind(other)
     })}
  end

  @doc """
  Deterministic origin of `subject`.

  `opts`: `:data` (already projected `%{text:, dialect:}`; projected here when absent),
  `:projection` (defaults to `#{inspect(__MODULE__)}`). The primary key is taken from the
  changeset's record (empty for queries and action inputs). A subject that cannot be projected
  yields an origin whose `:data_sha256` is the digest of the empty text and whose resource is
  the subject's struct module (falling back to this module).
  """
  @impl true
  @spec origin(term(), keyword()) :: Origin.t()
  def origin(subject, opts \\ []) do
    data =
      case Keyword.fetch(opts, :data) do
        {:ok, %{text: _} = given} ->
          given

        _ ->
          case data(subject, opts) do
            {:ok, projected} -> projected
            {:error, _} -> %{text: "", dialect: nil}
          end
      end

    resource = origin_resource(subject)

    Origin.new(
      resource: resource,
      action: origin_action(subject),
      primary_key: origin_pk(resource, subject),
      projection: Keyword.get(opts, :projection, __MODULE__),
      data_sha256: AshGraphLaw.Projection.input_digest(data),
      dialect: Map.get(data, :dialect)
    )
  end

  defp origin_resource(%{resource: resource}) when is_atom(resource) and not is_nil(resource), do: resource
  defp origin_resource(resource) when is_atom(resource) and not is_nil(resource), do: resource
  defp origin_resource(%{__struct__: mod}), do: mod
  defp origin_resource(_other), do: __MODULE__

  defp origin_action(%{action: %{name: name}}) when is_atom(name), do: name
  defp origin_action(_other), do: nil

  defp origin_pk(resource, %Ash.Changeset{data: record}) do
    resource |> Ash.Resource.Info.primary_key() |> Map.new(&{&1, Map.get(record || %{}, &1)}) |> drop_nil_pk()
  end

  defp origin_pk(_resource, _subject), do: %{}

  # A create changeset has no key yet: the origin records `%{}` rather than nil-valued keys.
  defp drop_nil_pk(pk), do: if(Enum.any?(pk, fn {_k, v} -> is_nil(v) end), do: %{}, else: pk)

  defp subject_kind(%{__struct__: mod}), do: mod
  defp subject_kind(other), do: other |> :erlang.term_to_binary() |> byte_size() |> then(&{:term, &1})

  defp render(lines) do
    text = lines |> Enum.uniq() |> Enum.sort() |> Enum.map_join(&(&1 <> "\n"))
    {:ok, %{text: text, dialect: "ntriples"}}
  end

  # -- IRIs -----------------------------------------------------------------

  defp subject_iri(resource, segment) do
    "<#{@ag}resource:#{iri_encode(inspect(resource))}:#{iri_encode(segment)}>"
  end

  defp predicate(slot), do: "<#{@ag}#{iri_encode(slot, ":")}>"

  defp pk_segment(resource, record) do
    values = resource |> Ash.Resource.Info.primary_key() |> Enum.map(&Map.get(record || %{}, &1))

    if values == [] or Enum.any?(values, &is_nil/1) do
      "new"
    else
      Enum.map_join(values, "-", &to_string/1)
    end
  end

  # Percent-encodes everything outside RFC 3986 unreserved plus the `keep` characters.
  defp iri_encode(value, keep \\ "") when is_binary(value) do
    for <<byte <- value>>, into: "" do
      if unreserved?(byte) or <<byte>> in String.graphemes(keep) do
        <<byte>>
      else
        "%" <> Base.encode16(<<byte>>)
      end
    end
  end

  defp unreserved?(b), do: b in ?a..?z or b in ?A..?Z or b in ?0..?9 or b in [?-, ?., ?_, ?~]

  # -- action and slot triples ------------------------------------------------

  defp action_lines(_iri, nil), do: []

  defp action_lines(iri, %{name: name, type: type}) do
    [
      triple(iri, predicate("action"), literal(Atom.to_string(name), "string")),
      triple(iri, predicate("actionType"), literal(Atom.to_string(type), "string"))
    ]
  end

  defp argument_slots(nil, _arguments), do: []

  defp argument_slots(%{arguments: declared}, arguments) do
    arguments = arguments || %{}

    declared
    |> Enum.reject(& &1.sensitive?)
    |> Enum.map(&{"arg:#{&1.name}", Map.get(arguments, &1.name)})
  end

  defp slot_lines(iri, slots) do
    Enum.flat_map(slots, fn {slot, value} -> value_lines(iri, slot, value) end)
  end

  defp value_lines(_iri, _slot, nil), do: []

  defp value_lines(iri, slot, values) when is_list(values), do: Enum.flat_map(values, &value_lines(iri, slot, &1))

  defp value_lines(iri, slot, value) when is_atom(value) and not is_boolean(value) do
    [
      triple(iri, predicate(slot), literal(Atom.to_string(value), "string")),
      triple(iri, predicate("atom"), literal(slot, "string"))
    ]
  end

  defp value_lines(iri, slot, value), do: [triple(iri, predicate(slot), typed(value))]

  defp triple(subject, predicate, object), do: "#{subject} #{predicate} #{object} ."

  # -- literals -------------------------------------------------------------

  defp typed(v) when is_boolean(v), do: literal(Atom.to_string(v), "boolean")
  defp typed(v) when is_integer(v), do: literal(Integer.to_string(v), "integer")
  defp typed(v) when is_float(v), do: literal(Float.to_string(v), "double")
  defp typed(v) when is_binary(v), do: literal(v, "string")
  defp typed(%DateTime{} = v), do: literal(DateTime.to_iso8601(v), "dateTime")
  defp typed(%NaiveDateTime{} = v), do: literal(NaiveDateTime.to_iso8601(v), "dateTime")
  defp typed(%Date{} = v), do: literal(Date.to_iso8601(v), "date")
  defp typed(%Time{} = v), do: literal(Time.to_iso8601(v), "string")
  defp typed(%Decimal{} = v), do: literal(Decimal.to_string(v, :normal), "decimal")
  defp typed(%Ash.CiString{} = v), do: literal(to_string(v), "string")
  defp typed(v), do: literal(inspect(v, limit: :infinity, printable_limit: :infinity), "string")

  defp literal(lexical, type), do: ~s("#{escape(lexical)}"^^<#{@xsd}#{type}>)

  defp escape(string) do
    if String.valid?(string) do
      for <<cp::utf8 <- string>>, into: "", do: escape_cp(cp)
    else
      # Not valid UTF-8: project the bytes as an inspected, escaped string.
      escape(inspect(string, limit: :infinity, printable_limit: :infinity))
    end
  end

  defp escape_cp(?\\), do: "\\\\"
  defp escape_cp(?"), do: "\\\""
  defp escape_cp(?\n), do: "\\n"
  defp escape_cp(?\r), do: "\\r"
  defp escape_cp(?\t), do: "\\t"
  defp escape_cp(cp) when cp < 0x20 or (cp >= 0x7F and cp <= 0xFFFF), do: "\\u" <> hex(cp, 4)
  defp escape_cp(cp) when cp > 0xFFFF, do: "\\U" <> hex(cp, 8)
  defp escape_cp(cp), do: <<cp::utf8>>

  defp hex(cp, width), do: cp |> Integer.to_string(16) |> String.upcase() |> String.pad_leading(width, "0")
end
