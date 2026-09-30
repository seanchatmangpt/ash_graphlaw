# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.ParityTest do
  @moduledoc """
  `mix ash_graphlaw.parity` against REAL scripted wasm engines passed with `--wasm`.

  The positive control runs first. The task passes overall only when the typed surface (P4..P8),
  the vendored registry (R1) and the examples also hold, which depends on the other lanes'
  generated files; so the control asserts what this task owns: P1..P3 pass for the exact registry
  surface, the report is written, and any raise names no engine-surface check.

  UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshGraphLaw.Test.ParityFixtures
  alias Mix.Tasks.AshGraphlaw.Parity, as: Task

  defp engine!(variant), do: ParityFixtures.write_engine!(variant, ParityFixtures.scratch_dir!("task"))

  defp run_task(argv) do
    parent = self()

    output =
      capture_io(fn ->
        result =
          try do
            Task.run(argv)
          rescue
            error in Mix.Error -> {:raised, error.message}
          end

        send(parent, {:result, result})
      end)

    receive do
      {:result, result} -> {result, output}
    end
  end

  defp report!(dir), do: dir |> Path.join("parity_report.json") |> File.read!() |> Jason.decode!()

  defp status(report, id), do: report["checks"] |> Enum.find(&(&1["id"] == id)) |> Map.fetch!("status")

  test "positive control: the exact registry surface passes P1..P3 and writes the evidence file" do
    dir = ParityFixtures.scratch_dir!("evidence")
    {result, output} = run_task(["--wasm", engine!(:exact), "--no-examples", "--evidence-dir", dir])

    report = report!(dir)
    assert Enum.map(["P1", "P2", "P3"], &status(report, &1)) == ["pass", "pass", "pass"]
    assert output =~ "P1\tpass"

    case result do
      :ok -> assert report["drift"] == [] and report["standing"] == "PARTIAL_ALIVE"
      {:raised, message} -> refute message =~ ~r/\bP[123]\b/
    end
  end

  test "--list prints every check id without loading an engine" do
    {result, output} = run_task(["--list"])

    assert result == :ok
    for id <- ~w(P1 P2 P3 P4 P5 P6 P7 P8 P9 R1), do: assert(output =~ ~r/^#{id}\t/m)
  end

  for {variant, id} <- [dropped_op: "P1", reordered: "P1", extra_dialect: "P2", bad_registry_sha: "P3"] do
    test "#{variant} raises [capability_parity_drift] naming #{id}" do
      dir = ParityFixtures.scratch_dir!("drift")
      {result, _output} = run_task(["--wasm", engine!(unquote(variant)), "--no-examples", "--evidence-dir", dir])

      assert {:raised, message} = result
      assert message =~ ~r/^\[capability_parity_drift\] .*\b#{unquote(id)}\b/
      assert unquote(id) in report!(dir)["drift"]
    end
  end

  test "an engine that cannot be loaded raises [wasm_not_vendored] and still writes a BLOCKED report" do
    dir = ParityFixtures.scratch_dir!("blocked")

    {result, _output} =
      run_task(["--wasm", "/nonexistent/parity/graphlaw.wasm", "--no-examples", "--evidence-dir", dir])

    assert {:raised, "[wasm_not_vendored]" <> _} = result
    assert report!(dir)["status"] == "BLOCKED"
  end

  test "unknown options and stray arguments raise [invalid_options]" do
    assert {{:raised, "[invalid_options]" <> _}, _} = run_task(["--bogus"])
    assert {{:raised, "[invalid_options]" <> _}, _} = run_task(["stray"])
  end
end
