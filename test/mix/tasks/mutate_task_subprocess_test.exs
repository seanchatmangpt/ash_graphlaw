# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.MutateTaskSubprocessTest do
  @moduledoc """
  `mix ash_graphlaw.mutate` in a REAL `mix` subprocess over the REAL killer suites.

  The mutation runner executes `test/negative/**` and `test/adversarial/**` with ExUnit, which is a
  singleton and cannot be re-entered from inside this suite, so the complete task (baseline run,
  live mutant, restore, verdict, JSON report, exit code) is observed from outside:
  `System.cmd("mix", ["ash_graphlaw.mutate", ...])` in the project root, `MIX_ENV=test`, sharing
  this run's build root so nothing is recompiled.

  The in-VM behavior of the task (blocked and unknown verdicts, report shape, argument handling)
  is in `mutate_task_test.exs`. The full catalog run is `:slow` (about 25 seconds per mutant):
  `mix test --include slow`.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks, real subprocess.
  use ExUnit.Case, async: false

  alias AshGraphLaw.Mutation.Catalog

  @root Path.expand("../../..", __DIR__)

  setup_all do
    assert System.find_executable("mix"), "mix is not on PATH; the subprocess tests need it"
    :ok
  end

  defp mix(args, env \\ []) do
    System.cmd("mix", args,
      cd: @root,
      env: [{"MIX_ENV", "test"}] ++ env,
      stderr_to_stdout: true
    )
  end

  defp evidence_dir do
    dir = Path.join(System.tmp_dir!(), "agl-mutate-sub-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # The killers log through Logger at debug; keep only the task's own verdict and tally lines.
  defp verdict_lines(output) do
    for line <- String.split(output, "\n"),
        String.starts_with?(line, ["MUTANT_KILLED\t", "MUTANT_SURVIVED\t", "BLOCKED\t", "UNKNOWN\t"]),
        do: line
  end

  describe "argument handling, exit codes" do
    test "positive control: --list exits 0 and lists every catalog entry as resolvable with real killers" do
      {output, status} = mix(["ash_graphlaw.mutate", "--list"])

      assert status == 0, output

      listed =
        for line <- String.split(output, "\n"), String.starts_with?(line, "AGL-MUT-"), do: String.split(line, "\t")

      assert Enum.map(listed, &hd/1) == Catalog.ids()

      for [_id, target, status_text, "killer_files=" <> count] <- listed do
        assert target =~ ~r/^AshGraphLaw\.\S+\/\d+$/
        assert status_text == "resolvable"
        assert String.to_integer(count) > 0, "#{target} has no killer files in the real project"
      end
    end

    test "an unknown mutation id exits non-zero and names the known ids" do
      {output, status} = mix(["ash_graphlaw.mutate", "--only", "AGL-MUT-999"])

      assert status != 0
      assert output =~ "unknown mutation ids [\"AGL-MUT-999\"]"
      assert output =~ "AGL-MUT-001"
    end

    test "an invalid option exits non-zero before anything runs" do
      {output, status} = mix(["ash_graphlaw.mutate", "--bogus"])

      assert status != 0
      assert output =~ "invalid options"
      assert verdict_lines(output) == []
    end
  end

  describe "a real run over the real killer suites" do
    @describetag :slow
    @describetag timeout: 600_000

    test "killed mutants: exit 0 under --require-killed, verdict lines, report and restored BEAM" do
      evidence = evidence_dir()

      {output, status} =
        mix([
          "ash_graphlaw.mutate",
          "--only",
          "AGL-MUT-004",
          "--only",
          "AGL-MUT-002",
          "--require-killed",
          "--evidence-dir",
          evidence
        ])

      assert status == 0, String.slice(output, -3_000, 3_000)

      lines = verdict_lines(output)
      assert [_, _] = lines

      assert Enum.any?(
               lines,
               &String.starts_with?(&1, "MUTANT_KILLED\tAGL-MUT-004\tAshGraphLaw.Authority.check_ceiling/2\t")
             )

      assert Enum.any?(
               lines,
               &String.starts_with?(&1, "MUTANT_KILLED\tAGL-MUT-002\tAshGraphLaw.EngineLoad.check_digest/2\t")
             )

      assert output =~ "tally: %{"
      assert output =~ "report: #{evidence}/mutation_report.json"

      report = evidence |> Path.join("mutation_report.json") |> File.read!() |> Jason.decode!()

      assert report["schema"] == "ash_graphlaw.mutation_report/1"
      assert report["tally"] == %{"blocked" => 0, "mutant_killed" => 2, "mutant_survived" => 0, "unknown" => 0}
      assert Enum.map(report["verdicts"], & &1["mutation_id"]) == ["AGL-MUT-002", "AGL-MUT-004"]

      for v <- report["verdicts"] do
        assert v["verdict"] == "mutant_killed"
        assert v["killed_by"] != []
        # the unmutated baseline was green and non-empty, the mutant run had failures
        assert v["baseline"]["failures"] == 0
        assert v["baseline"]["total"] > 0
        assert v["mutant"]["failures"] > 0
        # restoration is verified against the on-disk BEAM, not assumed
        assert v["restored"]["pristine"] == true
        assert v["restored"]["restored_md5"] == v["restored"]["original_md5"]
        assert v["applied"]["mutant_md5"] != v["applied"]["original_md5"]
        assert v["applied"]["clauses_mutated"] >= 1
        assert v["killer_files"] != []
      end
    end

    test "the report is a function of the verdicts: sorted keys, trailing newline" do
      evidence = evidence_dir()

      {_output, 0} =
        mix(["ash_graphlaw.mutate", "--only", "AGL-MUT-008", "--require-killed", "--evidence-dir", evidence])

      raw = File.read!(Path.join(evidence, "mutation_report.json"))
      assert String.ends_with?(raw, "\n")

      top = Jason.decode!(raw, objects: :ordered_objects)
      [first | _] = top["verdicts"]

      for object <- [top, first] do
        keys = Enum.map(object.values, &elem(&1, 0))
        assert keys == Enum.sort(keys)
      end
    end
  end
end
