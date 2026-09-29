# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation.RunnerContainmentTest do
  @moduledoc """
  The mutation runner compiles killer files with `Code.compile_file/1`, which evaluates arbitrary
  top-level code and redefines loaded modules. These tests court the containment gate
  (`Runner.admit_files/2`) with real files in a real scratch directory.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Mutation.Runner

  @moduletag :tmp_dir

  defp write!(dir, name, source) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
    path
  end

  test "positive control: a harmless test file inside the root is admitted", %{tmp_dir: root} do
    file =
      write!(
        root,
        "unit/ok_test.exs",
        "defmodule AshGraphLaw.Test.ContainmentBenign#{System.unique_integer([:positive])} do\nend\n"
      )

    assert :ok = Runner.admit_files([file], root)
  end

  test "a file outside the test root is refused before anything is compiled", %{tmp_dir: root} do
    outside = write!(Path.dirname(root), "outside_#{System.unique_integer([:positive])}_test.exs", "IO.puts(:never)\n")
    on_exit(fn -> File.rm(outside) end)

    assert {:error, {:path_outside_test_root, ^outside}} = Runner.admit_files([outside], root)
    # a path that only shares the root's prefix is outside too
    sibling = write!(Path.dirname(root), "#{Path.basename(root)}_sibling/x_test.exs", "1\n")
    on_exit(fn -> File.rm_rf(Path.dirname(sibling)) end)
    assert {:error, {:path_outside_test_root, _}} = Runner.admit_files([sibling], root)
  end

  test "`..` traversal out of the root is refused", %{tmp_dir: root} do
    escape = Path.join([root, "..", "escape_#{System.unique_integer([:positive])}_test.exs"])
    File.write!(escape, "1\n")
    on_exit(fn -> File.rm(Path.expand(escape)) end)

    assert {:error, {:path_outside_test_root, _}} = Runner.admit_files([escape], root)
  end

  test "a symlink inside the root is refused even when its target is inside the root", %{tmp_dir: root} do
    real = write!(root, "real_test.exs", "1\n")
    link = Path.join(root, "link_test.exs")
    :ok = File.ln_s(real, link)

    assert :ok = Runner.admit_files([real], root)
    assert {:error, {:path_outside_test_root, ^link}} = Runner.admit_files([link], root)
  end

  test "a file that would redefine a module loaded from lib/ is refused, and nothing is replaced", %{tmp_dir: root} do
    before = AshGraphLaw.Authority.module_info(:md5)

    file =
      write!(root, "evil_test.exs", """
      defmodule AshGraphLaw.Authority do
        def check_ceiling(_admission, _lease), do: :ok
      end
      """)

    assert {:error, {:module_conflict, AshGraphLaw.Authority, source}} = Runner.admit_files([file], root)
    assert source =~ "lib/ash_graphlaw/authority.ex"
    assert AshGraphLaw.Authority.module_info(:md5) == before
  end

  test "nested modules are resolved against their parent before the conflict check", %{tmp_dir: root} do
    file =
      write!(root, "nested_test.exs", """
      defmodule AshGraphLaw do
        defmodule Refusal do
        end
      end
      """)

    # `AshGraphLaw` and `AshGraphLaw.Refusal` are both loaded from lib/
    assert {:error, {:module_conflict, AshGraphLaw, _}} = Runner.admit_files([file], root)
  end

  test "a file naming only its own, unloaded modules is admitted; an unparsable one is left to the compiler", %{
    tmp_dir: root
  } do
    fresh = write!(root, "fresh_test.exs", "defmodule Fresh#{System.unique_integer([:positive])}Test do\nend\n")
    broken = write!(root, "broken_test.exs", "defmodule Broken do\n")

    assert :ok = Runner.admit_files([fresh, broken], root)
  end
end
