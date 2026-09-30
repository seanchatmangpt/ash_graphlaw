# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written property suite over the REAL engine.

defmodule AshGraphLaw.Property.CapabilityOpPropertyTest do
  @moduledoc """
  StreamData over data_spec/text inputs: a typed capability run against the REAL engine never
  raises and never returns anything but `{:ok, %Result{}}` (with `:raw` equal to the engine map)
  or `{:error, %AshGraphLaw.Refusal{}}` inside the closed code table.
  """
  use AshGraphLaw.Test.PropertyCase, async: false

  import AshGraphLaw.Test.CapabilityCase,
    only: [engine_opts!: 0, sample_turtle: 0, typed: 3, raw: 3, result_module: 1]

  @moduletag :wasm
  @moduletag :slow

  @runs 25

  setup do
    {:ok, opts: engine_opts!()}
  end

  # {op, fun turning generated text into args}
  @text_ops [
    {"sniff", &__MODULE__.sniff_args/1},
    {"parse", &__MODULE__.parse_args/1},
    {"convert", &__MODULE__.convert_args/1},
    {"canonical", &__MODULE__.canonical_args/1},
    {"sparql", &__MODULE__.sparql_args/1},
    {"shacl", &__MODULE__.shacl_args/1},
    {"entail", &__MODULE__.entail_args/1},
    {"n3", &__MODULE__.n3_args/1}
  ]

  def sniff_args(t), do: %{text: t}
  def parse_args(t), do: %{text: t, dialect: "turtle"}
  def convert_args(t), do: %{text: t, dialect: "turtle", to: "ntriples"}
  def canonical_args(t), do: %{data: %{text: t, dialect: "turtle"}}
  def sparql_args(t), do: %{data: %{text: sample_turtle()}, query: t}
  def shacl_args(t), do: %{data: %{text: sample_turtle()}, shapes: t}
  def entail_args(t), do: %{data: %{text: t, dialect: "turtle"}, regime: "rdfs"}
  def n3_args(t), do: %{text: t}

  defp assert_typed_or_refused(op, args, opts) do
    case typed(op, args, opts) do
      {:ok, result} ->
        module = result_module(op)
        assert %{__struct__: ^module} = result
        assert {:ok, raw} = raw(op, args, opts)
        assert result.raw == raw

      {:error, %Refusal{} = refusal} ->
        assert refusal.code in Refusal.codes()
        assert refusal.class == Refusal.class_of(refusal.code)
    end
  end

  describe "positive control" do
    test "well-formed input is ok for every text op", %{opts: opts} do
      for {op, build} <- @text_ops, op not in ["sparql", "shacl", "n3"] do
        assert {:ok, _} = typed(op, build.(sample_turtle()), opts), op
      end

      assert {:ok, _} = typed("sparql", %{data: %{text: sample_turtle()}, query: "ASK { ?s ?p ?o }"}, opts)
      assert {:ok, _} = typed("n3", %{text: "@prefix : <https://e/> . :a :b :c ."}, opts)
    end
  end

  describe "text inputs never crash a typed run" do
    property "arbitrary text into every text-taking op yields ok or a typed refusal", %{opts: opts} do
      check all(t <- text(), max_runs: max_runs(@runs)) do
        for {op, build} <- @text_ops do
          assert_typed_or_refused(op, build.(t), opts)
        end
      end
    end

    property "arbitrary text spliced into a valid Turtle document never crashes parse/canonical", %{opts: opts} do
      check all(t <- text(), max_runs: max_runs(@runs)) do
        doc = sample_turtle() <> "\n" <> t
        assert_typed_or_refused("parse", %{text: doc, dialect: "turtle"}, opts)
        assert_typed_or_refused("canonical", %{data: %{text: doc, dialect: "turtle"}}, opts)
      end
    end
  end

  describe "data_spec shapes never crash a typed run" do
    property "hint, base and dialect strings of any content are ok or refused", %{opts: opts} do
      check all(hint <- text(), base <- text(), dialect <- text(), max_runs: max_runs(@runs)) do
        data = %{text: sample_turtle(), hint: hint, base: base, dialect: dialect}
        assert_typed_or_refused("canonical", %{data: data}, opts)
        assert_typed_or_refused("shacl", %{data: data, shapes: sample_turtle()}, opts)
      end
    end

    property "arbitrary JSON in an object-typed slot is refused or answered, never raised", %{opts: opts} do
      check all(value <- json_map(), max_runs: max_runs(@runs)) do
        assert_typed_or_refused("datalog", %{rules: [value], facts: []}, opts)
        assert_typed_or_refused("law", %{data: %{text: sample_turtle()}, steps: [value]}, opts)
      end
    end

    property "every regime string of any content is answered or refused", %{opts: opts} do
      check all(regime <- text(), max_runs: max_runs(@runs)) do
        assert_typed_or_refused("entail", %{data: %{text: sample_turtle()}, regime: regime}, opts)
      end
    end
  end

  describe "client-side args never crash" do
    property "arbitrary top-level args are ok, or refused before the engine when malformed", %{opts: opts} do
      check all(args <- json_map(), max_runs: max_runs(100)) do
        for op <- ["sniff", "parse", "canonical", "hooks", "policy"] do
          assert_typed_or_refused(op, args, opts)
        end
      end
    end
  end
end
