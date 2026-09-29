# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.EvidenceTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admitted
  alias AshGraphLaw.Evidence

  @wasm_sha "30f6bc6eca9d125fe805f4c2643818ebb0a1471edec75ed0ed989c734397c645"
  @input_digest String.duplicate("ab", 32)

  defp admitted(extra \\ %{}) do
    Admitted.from_map(
      Map.merge(
        %{
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
        },
        extra
      )
    )
  end

  defp evidence(overrides \\ []) do
    opts = Keyword.merge([wasm_sha256: @wasm_sha, graphlaw_release: "v26.9.28"], overrides)
    Evidence.new(:ticket_shape, admitted(), @input_digest, opts)
  end

  describe "new/4" do
    test "positive control: binds admission, input digest and engine identity to an admitted result" do
      ev = evidence()

      assert %Evidence{admission: :ticket_shape, input_digest: @input_digest} = ev
      assert ev.wasm_sha256 == @wasm_sha
      assert ev.graphlaw_release == "v26.9.28"
      assert ev.standing == :PARTIAL_ALIVE
      refute ev.standing == :ALIVE
      assert ev.digest =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "carries the receipts and graph ids of the admitted result" do
      ev = evidence()
      assert length(ev.receipts) == 1
      assert ev.graph_ids == ["state-0", "state-1", "state-1"]
    end
  end

  describe "digest/1" do
    test "is 64 lowercase hex characters" do
      assert Evidence.digest(evidence()) =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "is stable: the same evidence always hashes to the same digest" do
      assert Evidence.digest(evidence()) == Evidence.digest(evidence())
      assert evidence().digest == evidence().digest
    end

    test "the recorded digest field agrees with digest/1" do
      ev = evidence()
      assert ev.digest == Evidence.digest(ev)
    end

    test "changing the input digest changes the evidence digest (bound to the exact input)" do
      a = evidence()

      b =
        Evidence.new(:ticket_shape, admitted(), String.duplicate("cd", 32),
          wasm_sha256: @wasm_sha,
          graphlaw_release: "v26.9.28"
        )

      refute Evidence.digest(a) == Evidence.digest(b)
    end

    test "changing the engine identity changes the digest" do
      refute Evidence.digest(evidence()) == Evidence.digest(evidence(wasm_sha256: String.duplicate("0", 64)))
    end

    test "changing the admission name changes the digest" do
      other =
        Evidence.new(:ticket_close, admitted(), @input_digest, wasm_sha256: @wasm_sha, graphlaw_release: "v26.9.28")

      refute Evidence.digest(evidence()) == Evidence.digest(other)
    end

    test "is independent of map key insertion order (canonical sorted-key encoding)" do
      keys = for i <- 1..60, do: "k#{String.pad_leading(Integer.to_string(i), 2, "0")}"
      ascending = Map.new(keys, &{&1, 1})
      descending = keys |> Enum.reverse() |> Map.new(&{&1, 1})

      a = Evidence.new(:ticket_shape, admitted(%{"receipts" => [ascending]}), @input_digest, wasm_sha256: @wasm_sha)
      b = Evidence.new(:ticket_shape, admitted(%{"receipts" => [descending]}), @input_digest, wasm_sha256: @wasm_sha)

      assert Evidence.digest(a) == Evidence.digest(b)
    end
  end

  describe "to_map/1" do
    test "has only string keys, in sorted order when listed" do
      map = Evidence.to_map(evidence())

      assert Enum.all?(Map.keys(map), &is_binary/1)
      assert Map.keys(map) == Enum.sort(Map.keys(map))
    end

    test "records the fields a verifier needs to bind evidence to input and engine" do
      map = Evidence.to_map(evidence())

      assert map["admission"] in [:ticket_shape, "ticket_shape"]
      assert map["input_digest"] == @input_digest
      assert map["wasm_sha256"] == @wasm_sha
      assert map["graphlaw_release"] == "v26.9.28"
      assert map["standing"] in [:PARTIAL_ALIVE, "PARTIAL_ALIVE"]
    end

    test "encodes to JSON deterministically" do
      assert Jason.encode!(Evidence.to_map(evidence())) == Jason.encode!(Evidence.to_map(evidence()))
    end
  end
end
