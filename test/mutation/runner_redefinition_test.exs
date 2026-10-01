# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation.RunnerRedefinitionTest do
  @moduledoc """
  The mutation runner compiles killer files that may redefine loaded modules. These tests drive
  the PUBLIC `Runner.run/2` (which admits before compiling and only then touches ExUnit, so a
  refused file never starts a nested run) with real files in a real scratch root.

  Covered: every module the catalog mutates, and every module of the mutation machinery, is
  refused when a file tries to redefine it; the refusal happens before any top-level code in the
  file runs; the loaded BEAM is unchanged afterwards.

  KNOWN GAPS (characterised, not endorsed): the gate parses `defmodule` forms, so a module
  created dynamically, and a file reached through a symlinked directory that points outside the
  root, are currently admitted. Those tests assert the CURRENT behaviour and are named
  `KNOWN GAP`; when the runner closes them, they fail and must be flipped to refusals.

  UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks.
  """

  use ExUnit.Case, async: false

  alias AshGraphLaw.Mutation
  alias AshGraphLaw.Mutation.{Catalog, Runner}

  @moduletag :tmp_dir

  defp write!(dir, name, source) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
    path
  end

  defp md5(module), do: module.module_info(:md5)

  test "positive control: a file naming only fresh modules is admitted by the gate", %{tmp_dir: root} do
    file = write!(root, "fresh_test.exs", "defmodule Fresh#{System.unique_integer([:positive])}Redef do\nend\n")
    assert :ok = Runner.admit_files([file], root)
  end

  test "Runner.run refuses redefining any module the catalog mutates, before compiling anything", %{tmp_dir: root} do
    modules = Catalog.entries() |> Enum.map(& &1.module) |> Enum.uniq()
    assert length(modules) >= 8

    for module <- modules do
      before = md5(module)
      marker = Path.join(root, "ran_#{System.unique_integer([:positive])}")

      file =
        write!(root, "#{System.unique_integer([:positive])}_test.exs", """
        File.write!(#{inspect(marker)}, "top-level code ran")

        defmodule #{inspect(module)} do
          def hijacked, do: true
        end
        """)

      assert {:error, {:module_conflict, ^module, source}} = Runner.run([file], test_root: root)
      assert source =~ "lib/", "#{inspect(module)} conflict names #{source}"
      refute File.exists?(marker), "top-level code of a refused file ran for #{inspect(module)}"
      assert md5(module) == before, "#{inspect(module)} was replaced"
      refute function_exported?(module, :hijacked, 0)
    end
  end

  test "the mutation machinery itself cannot be redefined by a killer file", %{tmp_dir: root} do
    for module <- [
          Mutation,
          Runner,
          Catalog,
          AshGraphLaw.Mutation.Verdict,
          AshGraphLaw.Mutation.Collector,
          Mix.Tasks.AshGraphlaw.Mutate
        ] do
      before = md5(module)
      file = write!(root, "#{System.unique_integer([:positive])}_test.exs", "defmodule #{inspect(module)} do\nend\n")

      assert {:error, {:module_conflict, ^module, _source}} = Runner.run([file], test_root: root)
      assert md5(module) == before
    end
  end

  test "a conflict in the second file stops the run before the first file is compiled", %{tmp_dir: root} do
    marker = Path.join(root, "first_ran")

    first =
      write!(
        root,
        "a_test.exs",
        "File.write!(#{inspect(marker)}, \"x\")\ndefmodule FirstOk#{System.unique_integer([:positive])} do\nend\n"
      )

    second = write!(root, "b_test.exs", "defmodule AshGraphLaw.Authority do\nend\n")

    assert {:error, {:module_conflict, AshGraphLaw.Authority, _}} = Runner.run([first, second], test_root: root)
    refute File.exists?(marker)
  end

  test "an outside-root file is refused by Runner.run with nothing executed", %{tmp_dir: root} do
    outside_dir = Path.join(System.tmp_dir!(), "agl-redef-outside-#{System.unique_integer([:positive])}")
    marker = Path.join(outside_dir, "ran")
    outside = write!(outside_dir, "x_test.exs", "File.write!(#{inspect(marker)}, \"x\")\n")
    on_exit(fn -> File.rm_rf!(outside_dir) end)

    assert {:error, {:path_outside_test_root, ^outside}} = Runner.run([outside], test_root: root)
    refute File.exists?(marker)
  end

  test "KNOWN GAP: a module created dynamically (Module.create) is not seen by the defmodule scan", %{tmp_dir: root} do
    file =
      write!(root, "dynamic_test.exs", """
      Module.create(AshGraphLaw.Authority, quote(do: def(hijacked, do: true)), Macro.Env.location(__ENV__))
      """)

    # CURRENT behaviour: admitted. This is the gap; flip to `{:error, {:module_conflict, ...}}` once closed.
    assert :ok = Runner.admit_files([file], root)
    # nothing was compiled by the gate itself, so the module is still the project's
    refute function_exported?(AshGraphLaw.Authority, :hijacked, 0)
  end

  test "KNOWN GAP: a file reached through a symlinked directory escaping the root is admitted", %{tmp_dir: root} do
    outside_dir = Path.join(System.tmp_dir!(), "agl-redef-linktarget-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside_dir)
    on_exit(fn -> File.rm_rf!(outside_dir) end)
    File.write!(Path.join(outside_dir, "x_test.exs"), "1\n")

    link = Path.join(root, "escape")
    :ok = File.ln_s(outside_dir, link)
    via_link = Path.join(link, "x_test.exs")

    # CURRENT behaviour: the expanded path is inside the root and the file itself is not a symlink.
    assert :ok = Runner.admit_files([via_link], root)
    # the real path is outside the root
    refute String.starts_with?(File.read_link!(link), root)
  end
end
