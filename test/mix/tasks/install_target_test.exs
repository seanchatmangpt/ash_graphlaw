# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack emits installer tests. The installer under test
# (`lib/mix/tasks/ash_graphlaw.install.ex`) is GENERATED from the ash-extension-pack template; a
# defect these tests find is fixed in ontology.ttl (aex installer target-mode individuals), never
# by editing the projection. These tests are the falsifier for that fix.

igniter_test_available? = Code.ensure_loaded?(Igniter.Test) and Code.ensure_loaded?(Igniter)

unless igniter_test_available? do
  IO.puts(:stderr, "[igniter] SKIPPING Mix.Tasks.AshGraphlaw.InstallTargetTest -- Igniter.Test is not loadable")
end

defmodule Mix.Tasks.AshGraphlaw.InstallTargetTest do
  @moduledoc """
  `mix ash_graphlaw.install --target My.Res` against a real in-memory Igniter project
  (`Igniter.Test.test_project/1`) with a real task run (`Igniter.compose_task/3`); assertions are on
  the real resulting sources and notices. No mocks, no interaction assertions.

  Contract asserted:

    * a `--target` run adds `AshGraphLaw.Resource` to the resource's `extensions:` (via the same
      `Spark.Igniter.add_extension/5` mechanism, proven independently below), wires the
      `AshGraphLaw.Formatter` plugin and `import_deps: [:ash_graphlaw]`, and adds the wasmex dep;
    * a second run over the applied result changes nothing (idempotent);
    * an existing `extensions:` list is merged into, never duplicated;
    * without `--target` the resource is untouched and the manual-instructions notice is printed.

  The `--target` tests are expected to FAIL until the installer defect (bare `extensions: [...]`
  inserted as a statement, Sourceror SyntaxError) is fixed in ontology.ttl. That failure is the
  point: the suspected ontology property is the aex installer target-mode individual that selects
  `Spark.Igniter.add_extension/5` instead of `Igniter.Code.Common.add_code/3`.
  """

  use ExUnit.Case, async: true

  import Igniter.Test

  @moduletag :igniter

  @path "lib/my/res.ex"

  @resource """
  defmodule My.Res do
    use Ash.Resource,
      domain: My.Domain,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key(:id)
    end
  end
  """

  @resource_with_extensions """
  defmodule My.Res do
    use Ash.Resource,
      domain: My.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [Other.Extension]

    attributes do
      uuid_primary_key(:id)
    end
  end
  """

  defp source_content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  defp project(resource \\ @resource), do: test_project(files: %{@path => resource})

  defp install(igniter, argv), do: Igniter.compose_task(igniter, "ash_graphlaw.install", argv)

  defp count(content, substring), do: length(String.split(content, substring)) - 1

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))

  describe "positive control: the mechanism the installer must use" do
    test "Spark.Igniter.add_extension/5 adds AshGraphLaw.Resource to the resource's extensions" do
      igniter = Spark.Igniter.add_extension(project(), My.Res, Ash.Resource, :extensions, AshGraphLaw.Resource)
      source = source_content(igniter, @path)

      assert source =~ "extensions: [AshGraphLaw.Resource]"
      assert parses?(source)
    end

    test "Spark.Igniter.add_extension/5 merges into an existing extensions list and is idempotent" do
      once =
        Spark.Igniter.add_extension(
          project(@resource_with_extensions),
          My.Res,
          Ash.Resource,
          :extensions,
          AshGraphLaw.Resource
        )

      source = source_content(once, @path)
      assert source =~ "Other.Extension"
      assert count(source, "AshGraphLaw.Resource") == 1

      twice =
        once
        |> apply_igniter!()
        |> Spark.Igniter.add_extension(My.Res, Ash.Resource, :extensions, AshGraphLaw.Resource)

      assert count(source_content(twice, @path), "AshGraphLaw.Resource") == 1
    end

    test "the installer task itself is loaded and takes --target" do
      {:module, Mix.Tasks.AshGraphlaw.Install} = Code.ensure_loaded(Mix.Tasks.AshGraphlaw.Install)
      assert Mix.Task.task_name(Mix.Tasks.AshGraphlaw.Install) == "ash_graphlaw.install"

      info = Mix.Tasks.AshGraphlaw.Install.info([], nil)
      assert Keyword.has_key?(info.schema, :target)
    end
  end

  describe "without --target (manual-notice path)" do
    setup do
      {:ok, igniter: install(project(), [])}
    end

    test "prints the manual-instructions notice naming the extension and --target", %{igniter: igniter} do
      assert Enum.any?(igniter.notices, &(&1 =~ "AshGraphLaw.Resource installed successfully!"))
      assert Enum.any?(igniter.notices, &(&1 =~ "extensions: [AshGraphLaw.Resource]"))
      assert Enum.any?(igniter.notices, &(&1 =~ "--target MyApp.SomeResource"))
    end

    test "leaves the resource module byte-identical and never raises", %{igniter: igniter} do
      assert_unchanged(igniter, @path)
    end

    test "still wires the formatter plugin, import_deps and the wasmex dependency", %{igniter: igniter} do
      formatter = source_content(igniter, ".formatter.exs")
      assert formatter =~ ":ash_graphlaw"
      assert formatter =~ "AshGraphLaw.Formatter"
      assert source_content(igniter, "mix.exs") =~ ~r/\{:wasmex,\s*"~> 0\.15/
    end
  end

  describe "with --target My.Res" do
    test "adds AshGraphLaw.Resource to extensions and the result is valid Elixir" do
      igniter = install(project(), ["--target", "My.Res"])
      source = source_content(igniter, @path)

      assert source =~ "extensions: [AshGraphLaw.Resource]"
      assert count(source, "AshGraphLaw.Resource") == 1
      assert parses?(source)
    end

    test "keeps the rest of the resource intact and adds at most one graphlaw block" do
      igniter = install(project(), ["--target", "My.Res"])
      source = source_content(igniter, @path)

      assert source =~ "domain: My.Domain"
      assert source =~ "data_layer: Ash.DataLayer.Ets"
      assert source =~ "uuid_primary_key(:id)"
      assert count(source, "graphlaw do") <= 1
    end

    test "wires the formatter plugin, import_deps and the wasmex dependency alongside the patch" do
      igniter = install(project(), ["--target", "My.Res"])

      formatter = source_content(igniter, ".formatter.exs")
      assert formatter =~ ":ash_graphlaw"
      assert formatter =~ "AshGraphLaw.Formatter"
      assert source_content(igniter, "mix.exs") =~ ~r/\{:wasmex,\s*"~> 0\.15/
    end

    test "a second run over the applied result changes nothing" do
      igniter =
        project()
        |> install(["--target", "My.Res"])
        |> apply_igniter!()
        |> install(["--target", "My.Res"])

      assert_unchanged(igniter)

      source = source_content(igniter, @path)
      assert count(source, "AshGraphLaw.Resource") == 1
      assert count(source, "graphlaw do") <= 1
      assert count(source_content(igniter, ".formatter.exs"), "AshGraphLaw.Formatter") == 1
      assert count(source_content(igniter, "mix.exs"), ":wasmex") == 1
    end

    test "an existing extensions list is merged into, not duplicated" do
      igniter = install(project(@resource_with_extensions), ["--target", "My.Res"])
      source = source_content(igniter, @path)

      assert source =~ "Other.Extension"
      assert source =~ "AshGraphLaw.Resource"
      assert count(source, "extensions:") == 1
      assert parses?(source)
    end

    test "the target given as a module name resolves to its file, other files stay untouched" do
      other = "defmodule My.Other do\n  def hi, do: :ok\nend\n"

      igniter =
        test_project(files: %{@path => @resource, "lib/my/other.ex" => other})
        |> install(["--target", "My.Res"])

      assert source_content(igniter, "lib/my/other.ex") == other
    end
  end
end
