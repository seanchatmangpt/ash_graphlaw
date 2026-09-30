# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Livebooks.SemanticIntegrityTest do
  @moduledoc """
  Every `*.livemd` of the repository is a real, runnable notebook: parseable, installing this
  checkout by path, free of pre-filled outputs, and evaluating against real Ash resources on the
  ETS data layer with the real `AshGraphLaw` pool and host. Nothing is stubbed.

  When the engine is not vendored the cells run their typed refusal path (`--allow-unvendored`);
  when it is vendored they run against the pinned engine. The verdict, not a skip, is the test.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test. async: false because notebooks
  # start the fixed-name AshGraphLaw.Pool.
  use AshGraphLaw.Test.Case, async: false

  alias Mix.Tasks.AshGraphlaw.TestLivebooks

  @root Path.expand("../..", __DIR__)
  @required ~w(
    ash_graphlaw.livemd
    documentation/how_to/ash_first.livemd
    documentation/how_to/handle_refusals_interactively.livemd
    documentation/how_to/replayable_admission_evidence.livemd
  )

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp notebooks, do: TestLivebooks.discover(@root)
  defp relative(path), do: Path.relative_to(path, @root)
  defp cells_of(path), do: path |> File.read!() |> TestLivebooks.cells()

  describe "discovery" do
    test "positive control: the four required notebooks exist and are discovered" do
      found = Enum.map(notebooks(), &relative/1)

      for required <- @required do
        assert File.regular?(Path.join(@root, required)), "#{required} is missing"
        assert required in found, "#{required} not discovered"
      end
    end

    test "every discovered notebook is one of the owned, named notebooks or a documented extra" do
      extras = Enum.map(notebooks(), &relative/1) -- @required

      for extra <- extras do
        assert String.ends_with?(extra, ".livemd")
        assert String.starts_with?(extra, "documentation/")
      end
    end
  end

  describe "every notebook is a well-formed livebook" do
    test "positive control: the cell parser sees cells in every notebook" do
      for path <- notebooks() do
        assert [_ | _] = cells_of(path), "#{relative(path)} has no elixir cells"
      end
    end

    test "carries an SPDX header, one H1, and a Mix.install cell that comes first" do
      for path <- notebooks() do
        text = File.read!(path)
        name = relative(path)

        assert text =~ "SPDX-License-Identifier: MIT", "#{name}: no SPDX identifier"
        assert text =~ ~r/^# \S/m, "#{name}: no H1"
        assert length(Regex.scan(~r/^# \S/m, text)) == 1, "#{name}: more than one H1"

        assert [%{install?: true} | rest] = cells_of(path), "#{name}: first cell is not Mix.install"
        refute Enum.any?(rest, & &1.install?), "#{name}: more than one Mix.install cell"
      end
    end

    test "Mix.install pulls ash_graphlaw by a path that resolves to this checkout" do
      for path <- notebooks() do
        name = relative(path)
        [%{code: install} | _] = cells_of(path)

        assert install =~ ~r/\{:ash_graphlaw,\s*path:/, "#{name}: no path dep on :ash_graphlaw"

        [_, expression] = Regex.run(~r/\{:ash_graphlaw,\s*path:\s*(.+?)\}/s, install)
        {resolved, _binding} = Code.eval_string(expression, [], file: path)

        assert Path.expand(resolved) == @root, "#{name}: path dep resolves to #{resolved}"
        assert File.regular?(Path.join(resolved, "mix.exs"))
      end
    end

    test "installs no livebook-only dependency" do
      for path <- notebooks() do
        [%{code: install} | _] = cells_of(path)
        refute install =~ ~r/kino|livebook/i, "#{relative(path)}: livebook-only dep in Mix.install"
      end
    end

    test "every cell is valid Elixir syntax" do
      for path <- notebooks(), cell <- cells_of(path) do
        assert {:ok, _quoted} = Code.string_to_quoted(cell.code, file: path, line: cell.line),
               "#{relative(path)} line #{cell.line}: cell does not parse"
      end
    end

    test "cell line numbers point at the cell's first source line" do
      for path <- notebooks() do
        lines = path |> File.read!() |> String.split("\n")

        for cell <- cells_of(path) do
          assert Enum.at(lines, cell.line - 2) =~ ~r/^```elixir/,
                 "#{relative(path)}: line #{cell.line} does not follow an elixir fence"
        end
      end
    end
  end

  describe "no fabricated output" do
    test "no pre-filled livebook outputs or result comments" do
      for path <- notebooks() do
        text = File.read!(path)
        name = relative(path)

        refute text =~ ~r/livebook:\{[^}]*"output"/, "#{name}: has an output marker"
        refute text =~ ~r/^\s*#\s*=>/m, "#{name}: has a '# =>' result comment"
        refute text =~ ~r/^\s*\{:ok, %AshGraphLaw\./m, "#{name}: prints a pasted struct"
      end
    end

    test "no notebook states an ALIVE claim" do
      for path <- notebooks() do
        text = path |> File.read!() |> String.replace(~r/PARTIAL_ALIVE/, "")
        refute text =~ ~r/standing\s+(is\s+)?`?:?ALIVE/, "#{relative(path)}: claims ALIVE standing"
      end
    end
  end

  describe "cells use real collaborators" do
    test "no mock, stub or patch library appears in any cell" do
      for path <- notebooks(), cell <- cells_of(path) do
        refute cell.code =~ ~r/\b(Mox|:meck|Mimic|patch\(|expect\()/,
               "#{relative(path)} line #{cell.line}: mock-style call"
      end
    end

    test "every notebook defines a real Ash resource on Ash.DataLayer.Ets" do
      for path <- notebooks() do
        code = path |> cells_of() |> Enum.map_join("\n", & &1.code)
        name = relative(path)

        assert code =~ "use Ash.Resource", "#{name}: defines no resource"
        assert code =~ "Ash.DataLayer.Ets", "#{name}: resource is not on the ETS data layer"
        assert code =~ "AshGraphLaw.Resource", "#{name}: no resource uses the graphlaw extension"
      end
    end

    test "every notebook talks to the real engine boundary" do
      for path <- notebooks() do
        code = path |> cells_of() |> Enum.map_join("\n", & &1.code)
        assert code =~ "AshGraphLaw.Pool.start_link", "#{relative(path)}: never starts the real pool"
      end
    end
  end

  describe "cells run" do
    test "positive control: every notebook evaluates without a cell exception" do
      flags = if wasm_available?(), do: [], else: ["--allow-unvendored"]

      assert :ok = TestLivebooks.run(flags ++ notebooks())

      passed = for {:mix_shell, :info, ["ok   " <> line]} <- drain(), do: line
      assert length(passed) == length(notebooks())
    end

    test "running the notebooks leaves no notebook module and no pool behind" do
      flags = if wasm_available?(), do: [], else: ["--allow-unvendored"]
      assert :ok = TestLivebooks.run(flags ++ notebooks())

      leaked =
        for {module, _} <- :code.all_loaded(),
            String.starts_with?(Atom.to_string(module), "Elixir.AshGraphLaw.LivebookRun"),
            do: module

      assert leaked == []
      assert Process.whereis(AshGraphLaw.Pool) == nil
    end

    test "running twice is independent: no redefinition collision between runs" do
      flags = if wasm_available?(), do: [], else: ["--allow-unvendored"]
      root = Path.join(@root, "ash_graphlaw.livemd")

      assert :ok = TestLivebooks.run(flags ++ [root])
      assert :ok = TestLivebooks.run(flags ++ [root])
    end
  end

  defp drain(acc \\ []) do
    receive do
      {:mix_shell, _, _} = message -> drain([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
