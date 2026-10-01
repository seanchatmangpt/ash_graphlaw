# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.ParityCourtNegativeTest do
  @moduledoc """
  The parity court must refuse drift. Killer of AGL-MUT-015 (`Parity.same_list?/2`) and AGL-MUT-016
  (`Parity.same_digest?/2`): with either guard gone, an injected drift no longer reports
  `capability_parity_drift` naming its check id and these tests fail.

  Every drift runs against a REAL scripted wasm engine (`AshGraphLaw.Test.ParityFixtures`). The
  positive control comes first: the exact registry surface passes P1..P3, so a drift verdict below
  is caused by the injected difference and by nothing else.

  UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks.
  """

  use ExUnit.Case, async: false

  alias AshGraphLaw.Parity
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Test.ParityFixtures

  defp run_variant(variant, extra \\ []) do
    dir = ParityFixtures.scratch_dir!("negative")
    path = ParityFixtures.write_engine!(variant, dir)
    Parity.run(Keyword.merge([wasm_path: path, examples: false], extra))
  end

  defp status(report, id), do: report["checks"] |> Enum.find(&(&1["id"] == id)) |> Map.fetch!("status")

  defp drift!(variant) do
    assert {:error, %{refusal: %Refusal{} = refusal, report: report}} = run_variant(variant)
    assert refusal.code == :capability_parity_drift
    assert report["status"] == "DRIFT"
    assert report["standing"] == "REFUSED"
    {refusal, report}
  end

  test "positive control: the exact registry surface passes P1, P2 and P3" do
    report =
      case run_variant(:exact) do
        {:ok, report} -> report
        {:error, %{report: report}} -> report
      end

    assert status(report, "P1") == "pass"
    assert status(report, "P2") == "pass"
    assert status(report, "P3") == "pass"
    refute "P1" in report["drift"] or "P2" in report["drift"] or "P3" in report["drift"]
  end

  test "a dropped op is capability_parity_drift at P1" do
    {refusal, report} = drift!(:dropped_op)

    assert "P1" in report["drift"]
    assert refusal.message =~ "P1"
    assert status(report, "P2") == "pass"
    p1 = Enum.find(report["checks"], &(&1["id"] == "P1"))
    assert [_dropped] = p1["evidence"]["missing"]
    assert p1["broken_term"] == "R_missing_identity"
  end

  test "a reordered op list is capability_parity_drift at P1, with nothing missing or extra" do
    {refusal, report} = drift!(:reordered)

    assert "P1" in report["drift"]
    assert refusal.message =~ "P1"
    p1 = Enum.find(report["checks"], &(&1["id"] == "P1"))
    assert p1["evidence"]["missing"] == []
    assert p1["evidence"]["unexpected"] == []
  end

  test "an extra dialect is capability_parity_drift at P2, and P1 still passes" do
    {refusal, report} = drift!(:extra_dialect)

    assert "P2" in report["drift"]
    assert refusal.message =~ "P2"
    assert status(report, "P1") == "pass"
  end

  test "a mismatched registry_sha256 is capability_parity_drift at P3 only among P1..P3" do
    {refusal, report} = drift!(:bad_registry_sha)

    assert "P3" in report["drift"]
    assert refusal.message =~ "P3"
    assert status(report, "P1") == "pass"
    assert status(report, "P2") == "pass"
    p3 = Enum.find(report["checks"], &(&1["id"] == "P3"))
    assert p3["evidence"]["mismatched"] == ["live_registry_sha256"]
    assert p3["evidence"]["live_registry_sha256"] == ParityFixtures.wrong_digest()
  end

  test "a live ABI mismatch is refused at R2 even when capability identity is otherwise canonical" do
    {refusal, report} = drift!(:bad_abi)

    assert "R2" in report["drift"]
    assert refusal.message =~ "R2"
    r2 = Enum.find(report["checks"], &(&1["id"] == "R2"))
    assert r2["evidence"]["expected"] == 1
    assert r2["evidence"]["live"] == 999
    assert r2["broken_term"] == "R_missing_identity"
  end

  test "no engine on disk is a typed blocked refusal with a report, never a pass or a skip" do
    assert {:error, %{refusal: %Refusal{code: :wasm_not_vendored}, report: report}} =
             Parity.run(wasm_path: "/nonexistent/parity/graphlaw.wasm", examples: false)

    assert report["status"] == "BLOCKED"
    assert report["standing"] == "BLOCKED"
    assert Enum.all?(report["checks"], &(&1["status"] == "blocked"))
    refute Enum.any?(report["checks"], &(&1["status"] == "pass"))
  end

  test "a missing registry module is drift on every check, not a crash" do
    assert {:error, %{refusal: %Refusal{code: :capability_parity_drift}, report: report}} =
             Parity.run(registry: Module.concat(["AshGraphLaw", "NoSuchRegistry"]), examples: false)

    assert report["drift"] == Parity.check_ids()
    assert Enum.all?(report["checks"], &Map.has_key?(&1["evidence"], "registry_unavailable"))
  end

  test "an unreadable examples file is drift at P9 when examples are enabled" do
    assert {:error, %{refusal: %Refusal{code: :capability_parity_drift}, report: report}} =
             run_variant(:exact, examples: true, examples_path: "/nonexistent/op-examples.json")

    assert "P9" in report["drift"]
  end

  test "an unreadable vendored registry JSON is drift at R1" do
    assert {:error, %{report: report}} =
             run_variant(:exact, registry_json_path: "/nonexistent/capability-registry.json")

    assert "R1" in report["drift"]
  end
end
