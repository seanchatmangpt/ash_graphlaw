# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago probe against the REAL engine.
#
# WO-07 (v26.10.31 wave, lane 7): does the pinned GraphLaw wasm engine honor
# `sh:closed true`? Wave-1 found zero evidentiary hits for sh:closed anywhere in
# lib/test/registry/examples, so this probe supplies the missing evidence directly:
#
#   M1  — closed shape + out-of-vocabulary triple  => conforms MUST be false
#   M1′ — same data, closure constraint removed    => conforms MUST be true
#   M0  — fully conforming data, both shape variants => conforms MUST be true
#
# M1 vs M1′ isolates sh:closed causality. If M1 returns conforms: true the engine
# IGNORES closure — verdict BLOCKED and dependent lanes fall back to the
# Elixir-native validator path (RSK-01).

defmodule AshGraphLaw.Integration.Capability.ShaclClosedProbeTest do
  @moduledoc false
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Shacl, as: Result

  @moduletag :wasm
  @moduletag :slow

  # Shapes graph: one NodeShape targeting ex:T with exactly one allowed property ex:p.
  # sh:ignoredProperties carries rdf:type (the target binding uses `a ex:T`).
  @closed_shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix ex: <https://e/> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
  ex:S a sh:NodeShape ;
    sh:targetClass ex:T ;
    sh:closed true ;
    sh:ignoredProperties ( rdf:type ) ;
    sh:property [ sh:path ex:p ] .
  """

  # M1′ control: identical except the closure constraint is removed.
  @open_shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix ex: <https://e/> .
  ex:S a sh:NodeShape ;
    sh:targetClass ex:T ;
    sh:property [ sh:path ex:p ] .
  """

  # Data carrying an out-of-vocabulary predicate ex:q on a targeted node.
  @oov_data """
  @prefix ex: <https://e/> . ex:s a ex:T ; ex:p 1 ; ex:q 2 .
  """

  # Fully in-vocabulary data.
  @conforming_data """
  @prefix ex: <https://e/> . ex:s a ex:T ; ex:p 1 .
  """

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "sh:closed probe" do
    @tag :shacl_closed_probe
    test "M1: closed shape flags out-of-vocabulary predicate (conforms: false)", %{opts: opts} do
      assert {:ok, %Result{conforms: false, results: results}} =
               API.shacl(%{shapes: @closed_shapes, data: %{text: @oov_data}}, opts)

      assert is_list(results) and results != []
    end

    @tag :shacl_closed_probe
    test "M1': open shape on the same data conforms (isolates sh:closed causality)", %{opts: opts} do
      assert {:ok, %Result{conforms: true}} =
               API.shacl(%{shapes: @open_shapes, data: %{text: @oov_data}}, opts)
    end

    @tag :shacl_closed_probe
    test "M0: conforming data passes under both closed and open shapes", %{opts: opts} do
      for shapes <- [@closed_shapes, @open_shapes] do
        assert {:ok, %Result{conforms: true, results: []}} =
                 API.shacl(%{shapes: shapes, data: %{text: @conforming_data}}, opts)
      end
    end
  end
end
