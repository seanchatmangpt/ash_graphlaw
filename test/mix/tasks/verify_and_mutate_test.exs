# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.VerifyAndMutateTest do
  @moduledoc """
  `mix ash_graphlaw.verify` in a scratch project directory (its manifest, its engine file) and the
  argument handling of `mix ash_graphlaw.mutate`. The engines are real, spec-valid WebAssembly
  modules from `AshGraphLaw.Test.WasmFixtures.scripted_engine/1`, loaded under the pin of their own
  digest. They answer with scripted JSON; nothing here says anything about the pinned GraphLaw.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks. The working directory is
  # process-global, so this module is async: false and always restores it.
  use ExUnit.Case, async: false

  alias AshGraphLaw.Test.WasmFixtures
  alias Mix.Tasks.AshGraphlaw.{Mutate, Verify}

  @capabilities_v1 Jason.encode!(%{"ok" => true, "abi_version" => 1})

  setup do
    dir = Path.join(System.tmp_dir!(), "agl-verify-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "priv/graphlaw"))
    cwd = File.cwd!()
    File.cd!(dir)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      File.cd!(cwd)
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp install!(engine_bytes, opts \\ []) do
    pin = Keyword.get(opts, :pin, WasmFixtures.sha256(engine_bytes))

    manifest = %{
      "schema" => "ash_graphlaw.graphlaw.manifest/v1",
      "abi_version" => Keyword.get(opts, :abi, 1),
      "artifact" => %{"file" => "graphlaw.wasm", "sha256" => pin, "url" => "https://example.invalid/x"}
    }

    File.write!("priv/graphlaw/MANIFEST.json", Jason.encode!(manifest))
    unless opts[:no_engine], do: File.write!("priv/graphlaw/graphlaw.wasm", engine_bytes)
  end

  defp verify, do: Verify.run([])

  describe "mix ash_graphlaw.verify" do
    test "positive control: an engine that meets its pin and reports the manifest ABI is VERIFIED" do
      install!(WasmFixtures.scripted_engine(call: {:json, @capabilities_v1}))

      verify()
      assert_received {:mix_shell, :info, ["engine admitted: sha256=" <> _]}
      assert_received {:mix_shell, :info, ["GraphLaw engine VERIFIED (abi_version 1)." <> _]}
    end

    test "an ABI version different from the manifest's is refused abi_version_mismatch" do
      install!(WasmFixtures.scripted_engine(call: {:json, @capabilities_v1}), abi: 2)
      assert_raise Mix.Error, ~r/\[abi_version_mismatch\].*reports 1.*pins 2/, &verify/0
    end

    test "an engine that does not meet the pin is refused wasm_digest_mismatch" do
      install!(WasmFixtures.scripted_engine(call: {:json, @capabilities_v1}), pin: String.duplicate("0", 64))
      assert_raise Mix.Error, ~r/\[wasm_digest_mismatch\]/, &verify/0
    end

    test "an absent engine is refused wasm_not_vendored, and says how to vendor" do
      install!(WasmFixtures.scripted_engine(), no_engine: true, pin: String.duplicate("a", 64))
      assert_raise Mix.Error, ~r/\[wasm_not_vendored\].*mix ash_graphlaw.vendor/s, &verify/0
    end

    test "a missing or malformed manifest is refused wasm_invalid" do
      File.rm_rf!("priv/graphlaw/MANIFEST.json")
      assert_raise Mix.Error, ~r/\[wasm_invalid\]/, &verify/0

      File.write!("priv/graphlaw/MANIFEST.json", ~s({"schema": "x"}))
      assert_raise Mix.Error, ~r/\[wasm_invalid\]/, &verify/0
    end

    test "a capabilities answer that is not an ok body is refused with its typed reason" do
      install!(WasmFixtures.scripted_engine(call: {:json, ~s({"hello":"world"})}))
      assert_raise Mix.Error, ~r/\[malformed_response\]/, &verify/0

      install!(
        WasmFixtures.scripted_engine(call: {:json, Jason.encode!(%{"ok" => true, "abi_version" => 1, "x" => 1})})
      )

      verify()
    end

    test "an engine that traps on the capabilities call is refused with the host's typed code" do
      install!(WasmFixtures.scripted_engine(call: :trap))
      assert_raise Mix.Error, ~r/\[call_trapped\]/, &verify/0
    end
  end

  describe "mix ash_graphlaw.mutate argument handling" do
    test "positive control: --list prints one resolvable line per catalog entry and loads nothing" do
      Mutate.run(["--list"])

      lines = for {:mix_shell, :info, [line]} <- drain_shell(), do: line
      assert length(lines) == length(AshGraphLaw.Mutation.Catalog.ids())

      assert Enum.any?(
               lines,
               &String.starts_with?(&1, "AGL-MUT-004\tAshGraphLaw.Authority.check_ceiling/2\tresolvable")
             )
    end

    test "--list --only narrows the listing" do
      Mutate.run(["--list", "--only", "AGL-MUT-014"])
      assert [{:mix_shell, :info, [line]}] = drain_shell()
      assert line =~ "AGL-MUT-014"
    end

    test "an unknown id and an invalid option are refused before anything runs" do
      assert_raise Mix.Error, ~r/unknown mutation ids \["AGL-MUT-999"\]/, fn ->
        Mutate.run(["--only", "AGL-MUT-999"])
      end

      assert_raise Mix.Error, ~r/invalid options/, fn -> Mutate.run(["--bogus"]) end
    end
  end

  defp drain_shell(acc \\ []) do
    receive do
      {:mix_shell, :info, _} = message -> drain_shell([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
