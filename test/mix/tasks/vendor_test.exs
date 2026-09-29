# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.VendorTest do
  @moduledoc """
  `mix ash_graphlaw.vendor` against a real scratch project directory.

  The task resolves `priv/graphlaw` from the current working directory, so each test runs in a
  temporary directory holding its own `MANIFEST.json` whose pin is the sha256 of a real fixture
  module (`AshGraphLaw.Test.WasmFixtures`). Nothing is downloaded and the real `priv/graphlaw` is
  never touched.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks. The working directory is
  # process-global, so this module is async: false and always restores it.
  use ExUnit.Case, async: false

  alias AshGraphLaw.Test.WasmFixtures
  alias Mix.Tasks.AshGraphlaw.Vendor

  @good WasmFixtures.admissible_surface()
  @bad WasmFixtures.foreign_imports()

  setup do
    dir = Path.join(System.tmp_dir!(), "agl-vendor-#{System.unique_integer([:positive])}")
    priv = Path.join(dir, "priv/graphlaw")
    File.mkdir_p!(priv)

    manifest = %{
      "schema" => "ash_graphlaw.graphlaw.manifest/v1",
      "artifact" => %{
        "file" => "graphlaw.wasm",
        "sha256" => WasmFixtures.sha256(@good),
        "url" => "https://example.invalid/x"
      }
    }

    File.write!(Path.join(priv, "MANIFEST.json"), Jason.encode!(manifest))

    cwd = File.cwd!()
    File.cd!(dir)

    on_exit(fn ->
      File.cd!(cwd)
      File.rm_rf!(dir)
    end)

    %{dir: dir, target: Path.join(priv, "graphlaw.wasm"), priv: priv}
  end

  defp write_candidate!(dir, name, bytes) do
    path = Path.join(dir, name)
    File.write!(path, bytes)
    path
  end

  defp quietly(fun) do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    fun.()
  end

  test "positive control: a candidate whose sha256 is the pin is installed, byte for byte", ctx do
    good = write_candidate!(ctx.dir, "good.wasm", @good)

    quietly(fn -> Vendor.run(["--from", good]) end)

    assert File.read!(ctx.target) == @good
    quietly(fn -> Vendor.run(["--check"]) end)
  end

  test "a candidate that does not match the pin is rejected and nothing is installed", ctx do
    bad = write_candidate!(ctx.dir, "bad.wasm", @bad)

    assert_raise Mix.Error, ~r/wasm_digest_mismatch.*rejected/s, fn ->
      quietly(fn -> Vendor.run(["--from", bad]) end)
    end

    refute File.exists?(ctx.target)
  end

  test "a rejected candidate never destroys a previously vendored, pin-verified engine", ctx do
    good = write_candidate!(ctx.dir, "good.wasm", @good)
    bad = write_candidate!(ctx.dir, "bad.wasm", @bad)

    # positive control: the good engine is vendored and verifies
    quietly(fn -> Vendor.run(["--from", good]) end)
    assert File.read!(ctx.target) == @good

    assert_raise Mix.Error, ~r/any vendored engine left untouched/, fn ->
      quietly(fn -> Vendor.run(["--from", bad]) end)
    end

    assert File.read!(ctx.target) == @good
    assert Path.wildcard(Path.join(ctx.priv, "*.partial-*")) == []
    # and it still passes the check that the pin is met
    quietly(fn -> Vendor.run(["--check"]) end)
  end

  test "--check reports a vendored file that has drifted from the pin", ctx do
    File.write!(ctx.target, @bad)

    assert_raise Mix.Error, ~r/wasm_digest_mismatch/, fn -> quietly(fn -> Vendor.run(["--check"]) end) end
  end

  test "--check reports an absent engine as wasm_not_vendored", _ctx do
    assert_raise Mix.Error, ~r/wasm_not_vendored/, fn -> quietly(fn -> Vendor.run(["--check"]) end) end
  end

  test "an unreadable --from path is refused with wasm_unreadable", ctx do
    assert_raise Mix.Error, ~r/wasm_unreadable/, fn ->
      quietly(fn -> Vendor.run(["--from", Path.join(ctx.dir, "missing.wasm")]) end)
    end
  end
end
