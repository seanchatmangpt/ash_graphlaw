# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.EvidenceOriginTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admitted
  alias AshGraphLaw.Evidence
  alias AshGraphLaw.Projection.Default
  alias AshGraphLaw.Test.Ticket

  @wasm_sha "30f6bc6eca9d125fe805f4c2643818ebb0a1471edec75ed0ed989c734397c645"
  @input_digest String.duplicate("ab", 32)

  # Digest and canonical JSON of the evidence below, computed from the pre-origin encoding
  # (independent oracle: sorted-key compact JSON hashed with SHA-256, before evidence.ex changed).
  @pre_origin_digest "d3c181481fb1adc0fbe57740c57f6b9e3723df78e74e9ab63a0d34fec5f31a09"

  defp admitted do
    Admitted.from_map(%{
      "states" => ["state-0", "state-1", "state-1"],
      "receipts" => [
        %{
          "step" => "shacl",
          "parent" => "state-0",
          "child" => "state-1",
          "added" => 0,
          "authority" => "purrdf::shapes",
          "revision" => "r1",
          "index" => 0
        }
      ],
      "nquads" => "<urn:a:x> <urn:a:p> <urn:a:y> <urn:g> .\n"
    })
  end

  defp evidence(extra \\ []) do
    opts = Keyword.merge([wasm_sha256: @wasm_sha, graphlaw_release: "v26.9.28"], extra)
    Evidence.new(:ticket_shape, admitted(), @input_digest, opts)
  end

  defp origin(title) do
    Default.origin(Ash.Changeset.for_create(Ticket, :open, %{title: title}))
  end

  describe "without an origin (regression)" do
    test "positive control: digest is byte-identical to the pre-origin encoding" do
      ev = evidence()
      assert ev.origin == nil
      assert ev.digest == @pre_origin_digest
      assert Evidence.digest(ev) == @pre_origin_digest
    end

    test "to_map has no origin key and canonical JSON is the pre-origin document" do
      map = Evidence.to_map(evidence())
      refute Map.has_key?(map, "origin")

      assert map |> Map.delete("digest") |> Evidence.canonical_json() ==
               ~s({"admission":"ticket_shape","graph_ids":["state-0","state-1","state-1"],) <>
                 ~s("graphlaw_release":"v26.9.28","input_digest":"#{@input_digest}","lease":null,) <>
                 ~s("receipts":[{"added":0,"authority":"purrdf::shapes","child":"state-1","index":0,) <>
                 ~s("parent":"state-0","revision":"r1","step":"shacl"}],"standing":"PARTIAL_ALIVE",) <>
                 ~s("wasm_sha256":"#{@wasm_sha}"})
    end
  end

  describe "with an origin" do
    test "digest differs from the origin-less digest and is self-consistent" do
      ev = evidence(origin: origin("t"))

      refute ev.digest == @pre_origin_digest
      assert ev.digest == Evidence.digest(ev)
    end

    test "to_map carries the origin map and canonical JSON is sorted-key" do
      ev = evidence(origin: origin("t"))
      map = Evidence.to_map(ev)

      assert map["origin"]["resource"] == "AshGraphLaw.Test.Ticket"
      json = Evidence.canonical_json(map)
      assert json =~ ~s("origin":{"action":"open","base":null,"data_sha256":")
      assert json =~ ~s("projection":"AshGraphLaw.Projection.Default","resource":"AshGraphLaw.Test.Ticket")
    end

    test "digest is stable for equal origins and moves with the origin" do
      assert evidence(origin: origin("t")).digest == evidence(origin: origin("t")).digest
      refute evidence(origin: origin("a")).digest == evidence(origin: origin("b")).digest
    end

    test "a non-origin :origin value raises" do
      assert_raise ArgumentError, ~r/:origin must be/, fn -> evidence(origin: %{"resource" => "x"}) end
    end
  end
end
