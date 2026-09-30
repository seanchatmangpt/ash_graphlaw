# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.ParityTest do
  @moduledoc """
  `AshGraphLaw.Parity` against REAL scripted wasm engines (`AshGraphLaw.Test.ParityFixtures`).

  The positive control runs first: an engine that answers `capabilities` with exactly the registry
  surface passes P1..P3. The typed-surface checks (P4..P8, R1) depend on the generated modules and
  the vendored registry, so this file asserts only the engine-facing checks and the report shape.

  UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks.
  """

  use ExUnit.Case, async: false

  alias AshGraphLaw.Capability.CanonicalJSON
  alias AshGraphLaw.Parity
  alias AshGraphLaw.Test.ParityFixtures

  defp run_variant(variant, extra \\ []) do
    dir = ParityFixtures.scratch_dir!("unit")
    path = ParityFixtures.write_engine!(variant, dir)
    Parity.run([wasm_path: path, examples: false] ++ extra)
  end

  defp report_of({:ok, report}), do: report
  defp report_of({:error, %{report: report}}), do: report

  defp status(report, id), do: report["checks"] |> Enum.find(&(&1["id"] == id)) |> Map.fetch!("status")

  describe "positive control" do
    test "an engine that answers with the exact registry surface passes P1, P2 and P3" do
      report = :exact |> run_variant() |> report_of()

      assert status(report, "P1") == "pass"
      assert status(report, "P2") == "pass"
      assert status(report, "P3") == "pass"
      assert report["schema"] == "ash_graphlaw.parity/1"
      assert report["engine"]["pinned"] == false
      assert is_binary(report["engine"]["wasm_sha256"])
    end

    test "P9 is reported not_run, never pass, when examples are disabled" do
      report = :exact |> run_variant() |> report_of()
      assert status(report, "P9") == "not_run"
      assert report["checks"] |> Enum.find(&(&1["id"] == "P9")) |> get_in(["evidence", "reason"]) =~ "no-examples"
    end

    test "every check id is present, in order, with a title and a status" do
      report = :exact |> run_variant() |> report_of()
      assert Enum.map(report["checks"], & &1["id"]) == Parity.check_ids()
      assert Parity.check_ids() == ~w(P1 P2 P3 P4 P5 P6 P7 P8 P9 R1)

      for check <- report["checks"] do
        assert is_binary(check["title"]) and check["status"] in ["pass", "drift", "not_run"]
        assert check["status"] == "drift" == is_binary(check["broken_term"])
      end
    end

    test "the standing is never ALIVE: parity of surfaces is at most PARTIAL_ALIVE" do
      report = :exact |> run_variant() |> report_of()
      assert report["standing"] in ["PARTIAL_ALIVE", "REFUSED"]
      refute report["standing"] == "ALIVE"
    end

    test "an engine older than v26.9.29 (no registry fields) reports registry_sha256 UNKNOWN, not drift" do
      report = :legacy |> run_variant() |> report_of()
      p3 = Enum.find(report["checks"], &(&1["id"] == "P3"))

      assert p3["status"] == "pass"
      assert p3["evidence"]["live_registry_sha256"] == "UNKNOWN"
    end
  end

  describe "comparison helpers" do
    test "same_list?/2 is order- and content-sensitive" do
      assert Parity.same_list?(["a", "b"], ["a", "b"])
      refute Parity.same_list?(["b", "a"], ["a", "b"])
      refute Parity.same_list?(["a"], ["a", "b"])
      refute Parity.same_list?(["a", "b", "c"], ["a", "b"])
      refute Parity.same_list?(nil, ["a"])
    end

    test "same_digest?/2 requires an equal binary" do
      digest = ParityFixtures.wrong_digest()
      assert Parity.same_digest?(digest, digest)
      refute Parity.same_digest?(nil, digest)
      refute Parity.same_digest?(digest <> "0", digest)
    end
  end

  describe "the evidence file" do
    test "write_report/2 writes canonical JSON that decodes to the report" do
      report = :exact |> run_variant() |> report_of()
      dir = ParityFixtures.scratch_dir!("evidence")

      assert {:ok, path} = Parity.write_report(report, Path.join(dir, "nested"))
      assert Path.basename(path) == "parity_report.json"

      raw = File.read!(path)
      assert raw == CanonicalJSON.encode(report) <> "\n"
      assert Jason.decode!(raw) == report
    end

    test "write_report/2 refuses, typed by a message, when the directory cannot be created" do
      dir = ParityFixtures.scratch_dir!("blocked")
      file = Path.join(dir, "a_file")
      File.write!(file, "x")

      assert {:error, message} = Parity.write_report(%{"schema" => "x"}, Path.join(file, "sub"))
      assert is_binary(message)
    end
  end
end
