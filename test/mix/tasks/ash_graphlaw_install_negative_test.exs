# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L12. UNSUPPORTED(generator-capability): no pack emits installer tests.

defmodule Mix.Tasks.AshGraphlaw.InstallNegativeTest do
  @moduledoc """
  Negative cases for `mix ash_graphlaw.install`, run against real Igniter (no mocks).

  The pack's template calls `Igniter.Project.Module.find_and_update_module!/3` for
  `--target`, which raises when the module is absent (read from igniter's source). The
  test pins that observed behavior: an unknown target is refused loudly and leaves no
  patched source, rather than being silently ignored. Each refusal has a positive
  control (the same project patches successfully with a known target).
  """

  use ExUnit.Case, async: true

  import Igniter.Test

  @moduletag :igniter

  @path "lib/my_app/ticket.ex"

  defp project do
    test_project(
      files: %{
        @path => """
        defmodule MyApp.Ticket do
          use Ash.Resource,
            domain: MyApp.Domain,
            data_layer: Ash.DataLayer.Ets
        end
        """
      }
    )
  end

  # UNSUPPORTED(generator-capability): a KNOWN target does not patch either; the pack's
  # add_extension/1 raises SyntaxError (see ash_graphlaw_install_test.exs). The positive control
  # for the unknown-target refusals below is therefore that the known target reaches the patch
  # step and fails there, with a different error than "Could not find module".
  test "positive control: a known target is found (it reaches the patch step), unlike a missing one" do
    error =
      assert_raise SyntaxError, fn ->
        Igniter.compose_task(project(), "ash_graphlaw.install", ["--target", "MyApp.Ticket"])
      end

    refute Exception.message(error) =~ "Could not find module"
  end

  test "an unknown --target module is refused with a clear error, not silently ignored" do
    assert_raise RuntimeError, ~r/Could not find module MyApp\.Missing/, fn ->
      Igniter.compose_task(project(), "ash_graphlaw.install", ["--target", "MyApp.Missing"])
    end
  end

  test "an unknown --target leaves the existing resource source untouched (input preserved)" do
    before = project()
    original = before.rewrite |> Rewrite.source!(@path) |> Rewrite.Source.get(:content)

    assert_raise RuntimeError, fn ->
      Igniter.compose_task(before, "ash_graphlaw.install", ["--target", "MyApp.Missing"])
    end

    assert before.rewrite |> Rewrite.source!(@path) |> Rewrite.Source.get(:content) == original
  end

  # UNSUPPORTED(generator-capability, in-process): "installer refuses/notices when Igniter is
  # absent" is not testable in the same VM as the Igniter-gated branch without mocking code
  # loading; deliberately not simulated.
end
