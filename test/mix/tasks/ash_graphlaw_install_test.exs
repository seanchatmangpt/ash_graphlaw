# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L12. The installer under test (`lib/mix/tasks/ash_graphlaw.install.ex`) is GENERATED
# by ash-extension-pack from templates/install.ex.tmpl; these tests are the hand-written
# residue that observes it. UNSUPPORTED(generator-capability): no pack emits installer tests.

igniter_test_available? = Code.ensure_loaded?(Igniter.Test) and Code.ensure_loaded?(Igniter)

unless igniter_test_available? do
  IO.puts(:stderr, "[igniter] SKIPPING Mix.Tasks.AshGraphlaw.InstallTest -- Igniter.Test is not loadable")
end

defmodule Mix.Tasks.AshGraphlaw.InstallTest do
  @moduledoc """
  Chicago-style coverage of `mix ash_graphlaw.install`: a real in-memory Igniter project
  (`Igniter.Test.test_project/1`), a real task run (`Igniter.compose_task/3`) and assertions
  on the real resulting sources and notices. No mocks, no interaction assertions.

  Only behavior present in the pack's `install.ex.tmpl` is asserted: the wasmex runtime
  dependency, the formatter `import_deps` / plugin wiring, the manual-notice fallback
  without `--target`, and the `--target` patch that inserts `extensions: [AshGraphLaw.Resource]`
  and a starter `graphlaw do` block.

  Not asserted, by design: the template inserts `extensions:` unconditionally (no
  detect-and-merge), so re-running `--target` against an already patched module is not
  idempotent and no test claims it is. Idempotence is asserted for the dependency and
  formatter wiring, which Igniter itself keeps idempotent.
  """

  use ExUnit.Case, async: true

  import Igniter.Test

  @moduletag :igniter

  @path "lib/my_app/ticket.ex"

  @resource """
  defmodule MyApp.Ticket do
    use Ash.Resource,
      domain: MyApp.Domain,
      data_layer: Ash.DataLayer.Ets
  end
  """

  defp source_content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  defp target_project, do: test_project(files: %{@path => @resource})

  describe "task identity" do
    test "the generated module is exposed as `ash_graphlaw.install` (taskModuleName seam)" do
      assert Mix.Task.task_name(Mix.Tasks.AshGraphlaw.Install) == "ash_graphlaw.install"
    end

    test "the generated module is a real Igniter task" do
      # igniter_task?/1 inspects exported functions, which needs the module loaded (the suite
      # loads modules lazily, so without this the answer depends on test order)
      {:module, Mix.Tasks.AshGraphlaw.Install} = Code.ensure_loaded(Mix.Tasks.AshGraphlaw.Install)
      assert Igniter.Mix.Task.igniter_task?(Mix.Tasks.AshGraphlaw.Install)
    end
  end

  describe "without --target (positive control)" do
    setup do
      {:ok, igniter: Igniter.compose_task(test_project(), "ash_graphlaw.install", [])}
    end

    test "adds the wasmex runtime requirement to mix.exs", %{igniter: igniter} do
      mix_exs = source_content(igniter, "mix.exs")
      assert mix_exs =~ ~r/\{:wasmex,\s*"~> 0\.15/
    end

    test "wires the formatter import_deps and plugin", %{igniter: igniter} do
      formatter = source_content(igniter, ".formatter.exs")
      assert formatter =~ ":ash_graphlaw"
      assert formatter =~ "AshGraphLaw.Formatter"
    end

    test "leaves a manual-instructions notice naming the extension and --target", %{igniter: igniter} do
      assert Enum.any?(igniter.notices, &(&1 =~ "AshGraphLaw.Resource installed successfully!"))
      assert Enum.any?(igniter.notices, &(&1 =~ "extensions: [AshGraphLaw.Resource]"))
      assert Enum.any?(igniter.notices, &(&1 =~ "--target MyApp.SomeResource"))
    end
  end

  describe "idempotence of dependency and formatter wiring" do
    test "a second run after applying the first yields no source changes" do
      igniter =
        test_project()
        |> Igniter.compose_task("ash_graphlaw.install", [])
        |> apply_igniter!()
        |> Igniter.compose_task("ash_graphlaw.install", [])

      assert_unchanged(igniter)
      assert count_occurrences(source_content(igniter, "mix.exs"), ":wasmex") == 1
      assert count_occurrences(source_content(igniter, ".formatter.exs"), "AshGraphLaw.Formatter") == 1
    end
  end

  describe "with --target" do
    # UNSUPPORTED(generator-capability): the pack's install.ex.tmpl (ash-extension-pack@caa4fe61,
    # `add_extension/1`) inserts the bare text `extensions: [AshGraphLaw.Resource]` with
    # Igniter.Code.Common.add_code/3, which parses it as a statement, and `extensions: [...]` is
    # not one. Observed: Sourceror raises SyntaxError. This characterization test pins the real
    # behavior with its exact error; when the pack is fixed it fails and must be replaced by
    # patch assertions (extension present, exactly one `graphlaw do`, dep and formatter wiring).
    test "pack defect: patching a target raises a SyntaxError from the generated add_extension/1" do
      assert_raise SyntaxError, ~r/syntax error before: extensions/, fn ->
        Igniter.compose_task(target_project(), "ash_graphlaw.install", ["--target", "MyApp.Ticket"])
      end
    end

    test "positive control for the characterization: the same project without --target succeeds" do
      igniter = Igniter.compose_task(target_project(), "ash_graphlaw.install", [])
      assert source_content(igniter, "mix.exs") =~ ~r/\{:wasmex,\s*"~> 0\.15/
      assert source_content(igniter, @path) == @resource
    end
  end

  describe "the test environment" do
    test "Igniter.Test is loadable: the installer tests run, they are never silently skipped" do
      assert Code.ensure_loaded?(Igniter.Test)
      assert Code.ensure_loaded?(Igniter)
    end
  end

  # UNSUPPORTED(generator-capability, in-process): the `else` branch of the generated file
  # (plain Mix.Task that prints manual instructions when Igniter is absent) is only defined
  # when `Code.ensure_loaded?(Igniter)` is false at compile time. It cannot be exercised
  # in the same VM as the Igniter branch without mocking code loading, so it is not tested.

  defp count_occurrences(content, substring) do
    length(String.split(content, substring)) - 1
  end
end
