# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.MutateTaskTest do
  @moduledoc """
  `mix ash_graphlaw.mutate` against the REAL mutation catalog, in a scratch working directory.

  The task resolves killer test files relative to the current directory, so a scratch directory
  chooses which killers exist without touching the real suite:

    * an empty scratch directory has no killers, so every catalog entry is a typed `blocked`
      verdict (`mutation_killers_missing`) and the report, tally and exit behavior are observed
      on real data;
    * a scratch `test/negative/` whose file redefines a module loaded from `lib/` is refused by
      the runner's containment gate, so the baseline is `unknown` and the real
      `AshGraphLaw.Authority` BEAM is asserted unchanged.

  The runs that execute the real killer suites (`mix ash_graphlaw.mutate` over `test/negative/**`
  and `test/adversarial/**`) need their own VM, because ExUnit is a singleton and cannot run inside
  this suite; they are in `mutate_task_subprocess_test.exs` (real `System.cmd("mix", ...)`).

  The working directory is process-global, so this module is `async: false` and always restores it.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks.
  use ExUnit.Case, async: false

  alias AshGraphLaw.Mutation
  alias AshGraphLaw.Mutation.{Catalog, Runner}
  alias Mix.Tasks.AshGraphlaw.Mutate

  setup do
    dir = Path.join(System.tmp_dir!(), "agl-mutate-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cwd = File.cwd!()
    File.cd!(dir)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      File.cd!(cwd)
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(dir)
    end)

    %{dir: dir, evidence: Path.join(dir, "evidence")}
  end

  defp lines(acc \\ []) do
    receive do
      {:mix_shell, :info, [line]} -> lines([line | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp report!(evidence), do: evidence |> Path.join("mutation_report.json") |> File.read!() |> Jason.decode!()

  defp write!(dir, name, source) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
    path
  end

  describe "a run with no killer files (every entry blocked, typed)" do
    test "positive control: every catalog target resolves, so the block is the missing killers, not the target" do
      resolution = Catalog.resolution()
      assert length(resolution) == length(Catalog.ids())
      assert Enum.all?(resolution, &(&1.target_status == :resolvable))
    end

    test "each entry is reported blocked with mutation_killers_missing, one line per entry", ctx do
      Mutate.run(["--evidence-dir", ctx.evidence])

      out = lines()
      verdict_lines = Enum.filter(out, &String.starts_with?(&1, "BLOCKED\t"))
      assert length(verdict_lines) == length(Catalog.ids())

      for id <- Catalog.ids() do
        assert Enum.any?(verdict_lines, &String.starts_with?(&1, "BLOCKED\t#{id}\t")),
               "no BLOCKED line for #{id}"
      end

      assert Enum.all?(verdict_lines, &(&1 =~ "no killer test file for"))
    end

    test "the evidence dir receives a canonical JSON report with the documented shape", ctx do
      Mutate.run(["--evidence-dir", ctx.evidence])

      raw = File.read!(Path.join(ctx.evidence, "mutation_report.json"))
      assert String.ends_with?(raw, "\n")

      report = Jason.decode!(raw)
      assert report["schema"] == "ash_graphlaw.mutation_report/1"

      assert report["tally"] ==
               %{
                 "blocked" => length(Catalog.ids()),
                 "mutant_killed" => 0,
                 "mutant_survived" => 0,
                 "unknown" => 0
               }

      ids = Enum.map(report["verdicts"], & &1["mutation_id"])
      assert ids == Catalog.ids()

      for v <- report["verdicts"] do
        assert v["verdict"] == "blocked"
        assert v["code"] == "mutation_killers_missing"
        assert v["killers"] == Catalog.killers()
        assert v["killer_files"] == []
        assert v["target"] =~ ~r/^AshGraphLaw\.\S+\.\w+[?!]?\/\d+$/
      end
    end

    test "the report is byte-identical across runs (canonical, sorted keys)", ctx do
      Mutate.run(["--evidence-dir", Path.join(ctx.evidence, "a")])
      Mutate.run(["--evidence-dir", Path.join(ctx.evidence, "b")])

      assert File.read!(Path.join(ctx.evidence, "a/mutation_report.json")) ==
               File.read!(Path.join(ctx.evidence, "b/mutation_report.json"))
    end

    test "the tally and report path are printed", ctx do
      Mutate.run(["--evidence-dir", ctx.evidence])

      out = lines()
      assert Enum.any?(out, &(&1 =~ "blocked: #{length(Catalog.ids())}"))
      assert ("report: " <> Path.join(Path.expand(ctx.evidence), "mutation_report.json")) in out
    end

    test "--only restricts the run and the report to the selected ids", ctx do
      Mutate.run(["--only", "AGL-MUT-004", "--only", "AGL-MUT-002", "--evidence-dir", ctx.evidence])

      ids = for v <- report!(ctx.evidence)["verdicts"], do: v["mutation_id"]
      assert ids == ["AGL-MUT-002", "AGL-MUT-004"]
    end

    test "without --evidence-dir the report goes to a fresh tmp dir that the task names" do
      Mutate.run(["--only", "AGL-MUT-004"])

      assert Enum.find_value(lines(), fn
               "report: " <> path -> path
               _ -> nil
             end)
             |> then(fn path ->
               on_exit(fn -> File.rm_rf(Path.dirname(path)) end)
               assert Path.basename(path) == "mutation_report.json"
               assert Path.dirname(path) =~ "ash_graphlaw-mutate-"
               assert File.regular?(path)
             end)
    end

    test "--require-killed turns a non-killed verdict into a failed run, after the report is written", ctx do
      # positive control: without the flag the same run succeeds
      assert :ok = Mutate.run(["--only", "AGL-MUT-004", "--evidence-dir", ctx.evidence])
      File.rm_rf!(ctx.evidence)

      assert_raise Mix.Error, ~r/not every selected mutant was killed: %\{.*blocked: 1/, fn ->
        Mutate.run(["--only", "AGL-MUT-004", "--evidence-dir", ctx.evidence, "--require-killed"])
      end

      assert report!(ctx.evidence)["tally"]["blocked"] == 1
    end

    test "no catalog module is left mutated by a run" do
      Mutate.run([])

      modules = Catalog.entries() |> Enum.map(& &1.module) |> Enum.uniq()
      assert Enum.all?(modules, &Mutation.pristine?/1)
    end
  end

  describe "--list" do
    test "positive control: every line is id, target, resolvable and the killer file count" do
      Mutate.run(["--list"])

      out = lines()
      assert length(out) == length(Catalog.ids())
      assert Enum.all?(out, &(&1 =~ ~r/^AGL-MUT-\d{3}\tAshGraphLaw\.\S+\/\d+\tresolvable\tkiller_files=0$/))
    end

    test "killer_files counts what the current directory holds", ctx do
      write!(ctx.dir, "test/negative/a_test.exs", "# empty\n")
      write!(ctx.dir, "test/adversarial/b_test.exs", "# empty\n")

      Mutate.run(["--list", "--only", "AGL-MUT-001"])

      assert [line] = lines()
      assert String.ends_with?(line, "killer_files=2")
    end

    test "--list writes no report", ctx do
      Mutate.run(["--list", "--evidence-dir", ctx.evidence])
      refute File.exists?(ctx.evidence)
    end
  end

  describe "a killer file that redefines a module loaded from lib/" do
    setup ctx do
      file =
        write!(ctx.dir, "test/negative/redefine_test.exs", """
        defmodule AshGraphLaw.Authority do
          def check_ceiling(_admission, _lease), do: :ok
        end
        """)

      %{redefiner: file}
    end

    test "positive control: a benign killer file is admitted by the containment gate", ctx do
      benign =
        write!(
          ctx.dir,
          "test/negative/benign_test.exs",
          "defmodule AshGraphLaw.Test.MutateTaskBenign#{System.unique_integer([:positive])} do\nend\n"
        )

      assert :ok = Runner.admit_files([benign], Path.join(ctx.dir, "test"))
    end

    test "the runner refuses it, the baseline is unknown, and the real BEAM is untouched", ctx do
      before = AshGraphLaw.Authority.module_info(:md5)

      Mutate.run(["--only", "AGL-MUT-004", "--evidence-dir", ctx.evidence])

      assert [verdict] = report!(ctx.evidence)["verdicts"]
      assert verdict["verdict"] == "unknown"
      assert verdict["detail"] =~ "baseline not green"
      assert verdict["detail"] =~ "module_conflict"
      assert verdict["detail"] =~ "AshGraphLaw.Authority"
      assert [killer_file] = verdict["killer_files"]
      assert Path.basename(killer_file) == Path.basename(ctx.redefiner)
      assert verdict["baseline"]["error"] =~ "module_conflict"

      assert AshGraphLaw.Authority.module_info(:md5) == before
      assert Mutation.pristine?(AshGraphLaw.Authority)
    end

    test "--require-killed fails the run on the unknown verdict", ctx do
      assert_raise Mix.Error, ~r/not every selected mutant was killed: %\{.*unknown: 1/, fn ->
        Mutate.run(["--only", "AGL-MUT-004", "--evidence-dir", ctx.evidence, "--require-killed"])
      end

      assert [%{"verdict" => "unknown"}] = report!(ctx.evidence)["verdicts"]
    end

    test "entries sharing one killer set share one baseline; each is unknown, none is a pass", ctx do
      Mutate.run(["--only", "AGL-MUT-002", "--only", "AGL-MUT-003", "--evidence-dir", ctx.evidence])

      verdicts = report!(ctx.evidence)["verdicts"]
      assert Enum.map(verdicts, & &1["verdict"]) == ["unknown", "unknown"]
      assert verdicts |> Enum.map(& &1["baseline"]) |> Enum.uniq() |> length() == 1
    end
  end

  describe "argument handling" do
    test "an unknown id is refused before anything runs and no report is written", ctx do
      assert_raise Mix.Error, ~r/unknown mutation ids \["AGL-MUT-999"\]; known: \["AGL-MUT-001"/, fn ->
        Mutate.run(["--only", "AGL-MUT-999", "--evidence-dir", ctx.evidence])
      end

      refute File.exists?(ctx.evidence)
    end

    test "one unknown id among known ones refuses the whole run", ctx do
      assert_raise Mix.Error, ~r/unknown mutation ids \["AGL-MUT-000"\]/, fn ->
        Mutate.run(["--only", "AGL-MUT-004", "--only", "AGL-MUT-000", "--evidence-dir", ctx.evidence])
      end

      refute File.exists?(ctx.evidence)
    end

    test "an invalid option is refused" do
      assert_raise Mix.Error, ~r/invalid options: \[\{"--bogus", nil\}\]/, fn -> Mutate.run(["--bogus"]) end
    end

    test "the mutate task itself is protected machinery: it can never be a mutation target" do
      assert Mutation.protected?(Mix.Tasks.AshGraphlaw.Mutate)
      refute Enum.any?(Catalog.entries(), &(&1.module == Mix.Tasks.AshGraphlaw.Mutate))
    end
  end
end
