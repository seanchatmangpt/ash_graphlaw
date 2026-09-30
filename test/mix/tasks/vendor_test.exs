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

  describe "reporting and idempotence" do
    test "a successful vendoring reports source, size and pin", ctx do
      good = write_candidate!(ctx.dir, "good.wasm", @good)

      quietly(fn -> Vendor.run(["--from", good]) end)

      assert_received {:mix_shell, :info, [report]}
      assert report =~ "vendored #{ctx.target}"
      assert report =~ "source=#{good}"
      assert report =~ "bytes=#{byte_size(@good)}"
      assert report =~ "sha256=#{WasmFixtures.sha256(@good)}"
    end

    test "--check on a verified engine reports OK with the pin and writes nothing", ctx do
      good = write_candidate!(ctx.dir, "good.wasm", @good)
      quietly(fn -> Vendor.run(["--from", good]) end)
      before = File.stat!(ctx.target).mtime

      quietly(fn -> Vendor.run(["--check"]) end)

      assert_received {:mix_shell, :info, ["graphlaw.wasm OK sha256=" <> pin]}
      assert pin == WasmFixtures.sha256(@good)
      assert File.stat!(ctx.target).mtime == before
      assert Path.wildcard(Path.join(ctx.priv, "*.partial-*")) == []
    end

    test "vendoring twice is idempotent and leaves no partial file", ctx do
      good = write_candidate!(ctx.dir, "good.wasm", @good)

      quietly(fn ->
        Vendor.run(["--from", good])
        Vendor.run(["--from", good])
      end)

      assert File.read!(ctx.target) == @good
      assert Path.wildcard(Path.join(ctx.priv, "*.partial-*")) == []
      assert File.ls!(ctx.priv) |> Enum.sort() == ["MANIFEST.json", "graphlaw.wasm"]
    end

    test "a drifted engine is replaced by a candidate that meets the pin", ctx do
      good = write_candidate!(ctx.dir, "good.wasm", @good)
      File.write!(ctx.target, @bad)
      assert_raise Mix.Error, ~r/wasm_digest_mismatch/, fn -> quietly(fn -> Vendor.run(["--check"]) end) end

      quietly(fn -> Vendor.run(["--from", good]) end)

      assert File.read!(ctx.target) == @good
      quietly(fn -> Vendor.run(["--check"]) end)
    end

    test "the target's parent directory is created when the manifest names a nested file", ctx do
      manifest = %{
        "schema" => "ash_graphlaw.graphlaw.manifest/v1",
        "artifact" => %{
          "file" => "engine/v1/graphlaw.wasm",
          "sha256" => WasmFixtures.sha256(@good),
          "url" => "https://example.invalid/x"
        }
      }

      File.write!(Path.join(ctx.priv, "MANIFEST.json"), Jason.encode!(manifest))
      good = write_candidate!(ctx.dir, "good.wasm", @good)
      refute File.dir?(Path.join(ctx.priv, "engine"))

      quietly(fn -> Vendor.run(["--from", good]) end)
      assert File.read!(Path.join(ctx.priv, "engine/v1/graphlaw.wasm")) == @good
    end

    test "an uppercase pin in the manifest is compared case-insensitively", ctx do
      manifest = %{
        "schema" => "ash_graphlaw.graphlaw.manifest/v1",
        "artifact" => %{
          "file" => "graphlaw.wasm",
          "sha256" => String.upcase(WasmFixtures.sha256(@good)),
          "url" => "https://example.invalid/x"
        }
      }

      File.write!(Path.join(ctx.priv, "MANIFEST.json"), Jason.encode!(manifest))
      good = write_candidate!(ctx.dir, "good.wasm", @good)

      quietly(fn -> Vendor.run(["--from", good]) end)
      assert File.read!(ctx.target) == @good
    end

    test "the manifest may name a different target file", ctx do
      manifest = %{
        "schema" => "ash_graphlaw.graphlaw.manifest/v1",
        "artifact" => %{
          "file" => "engine.bin",
          "sha256" => WasmFixtures.sha256(@good),
          "url" => "https://example.invalid/x"
        }
      }

      File.write!(Path.join(ctx.priv, "MANIFEST.json"), Jason.encode!(manifest))
      good = write_candidate!(ctx.dir, "good.wasm", @good)

      quietly(fn -> Vendor.run(["--from", good]) end)
      assert File.read!(Path.join(ctx.priv, "engine.bin")) == @good
      refute File.exists?(ctx.target)
    end

    test "--check wins over --from: it verifies and writes nothing", ctx do
      good = write_candidate!(ctx.dir, "good.wasm", @good)

      assert_raise Mix.Error, ~r/wasm_not_vendored/, fn ->
        quietly(fn -> Vendor.run(["--check", "--from", good]) end)
      end

      refute File.exists?(ctx.target)
    end
  end

  describe "manifest refusals" do
    test "positive control: the scratch manifest is accepted", ctx do
      good = write_candidate!(ctx.dir, "good.wasm", @good)
      quietly(fn -> Vendor.run(["--from", good]) end)
      assert File.regular?(ctx.target)
    end

    test "an absent manifest is wasm_unreadable", ctx do
      File.rm!(Path.join(ctx.priv, "MANIFEST.json"))
      assert_raise Mix.Error, ~r/\[wasm_unreadable\] cannot read manifest.*enoent/s, fn -> Vendor.run(["--check"]) end
    end

    test "a manifest with another schema is wasm_invalid", ctx do
      File.write!(Path.join(ctx.priv, "MANIFEST.json"), ~s({"schema":"other/v9","artifact":{}}))

      assert_raise Mix.Error, ~r/\[wasm_invalid\].*ash_graphlaw.graphlaw.manifest\/v1/s, fn ->
        Vendor.run(["--check"])
      end
    end

    test "a manifest that is not JSON is refused as wasm_unreadable with the decode error", ctx do
      File.write!(Path.join(ctx.priv, "MANIFEST.json"), "not json {")
      assert_raise Mix.Error, ~r/\[wasm_unreadable\].*DecodeError/s, fn -> Vendor.run(["--check"]) end
    end

    test "a manifest whose artifact fields are not strings is wasm_invalid", ctx do
      manifest = %{
        "schema" => "ash_graphlaw.graphlaw.manifest/v1",
        "artifact" => %{"file" => "graphlaw.wasm", "sha256" => 7, "url" => "https://example.invalid/x"}
      }

      File.write!(Path.join(ctx.priv, "MANIFEST.json"), Jason.encode!(manifest))
      assert_raise Mix.Error, ~r/\[wasm_invalid\]/, fn -> Vendor.run(["--check"]) end
    end

    test "an unknown option is refused before anything is read" do
      assert_raise OptionParser.ParseError, ~r/--bogus/, fn -> Vendor.run(["--bogus"]) end
    end
  end

  describe "sha256_hex/1" do
    test "matches the published SHA-256 test vectors" do
      assert Vendor.sha256_hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      assert Vendor.sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    end

    test "agrees with the fixture helper on real wasm bytes" do
      assert Vendor.sha256_hex(@good) == WasmFixtures.sha256(@good)
    end
  end
end
