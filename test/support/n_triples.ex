# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.NTriples do
  @moduledoc """
  UNSUPPORTED(generator-capability): test-only N-Triples writer.

  Builds well-formed N-Triples text from `{subject, predicate, object}` tuples so tests
  can construct real GraphLaw input without string-splicing escapes by hand.

    * subject / predicate are IRI strings (no angle brackets);
    * an object is an IRI string, `{:lit, text}` (plain literal) or `{:lit, text, datatype_iri}`.
  """

  @doc "Renders triples as sorted-by-input N-Triples text, one line per triple."
  @spec render([{String.t(), String.t(), term()}]) :: String.t()
  def render(triples) when is_list(triples) do
    Enum.map_join(triples, fn {s, p, o} -> "<#{s}> <#{p}> #{object(o)} .\n" end)
  end

  @doc "Escapes a string for use inside an N-Triples literal."
  @spec escape(String.t()) :: String.t()
  def escape(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> Enum.map_join(fn
      ?\\ -> "\\\\"
      ?" -> "\\\""
      ?\n -> "\\n"
      ?\r -> "\\r"
      ?\t -> "\\t"
      c -> <<c::utf8>>
    end)
  end

  defp object({:lit, text}), do: "\"#{escape(text)}\""
  defp object({:lit, text, datatype}), do: "\"#{escape(text)}\"^^<#{datatype}>"
  defp object(iri) when is_binary(iri), do: "<#{iri}>"
end
