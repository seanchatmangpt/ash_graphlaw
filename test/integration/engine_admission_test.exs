# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.EngineAdmissionTest do
  @moduledoc """
  Engine admission before instantiation, against the real pinned module and
  hand-assembled foreign modules (real bytes, real Wasmex compile).
  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{EngineLoad, Host, Refusal, WasmConfig}

  @moduletag :wasm

  # magic + version, empty module: no imports, no exports
  @empty_module <<0, 97, 115, 109, 1, 0, 0, 0>>
  # type section (() -> ()) + import section importing env.f
  @foreign_import <<0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 2, 9, 1, 3, "env", 1, "f", 0, 0>>

  defp real_bytes, do: File.read!(wasm_path())
  defp sha(bin), do: Base.encode16(:crypto.hash(:sha256, bin), case: :lower)

  test "the real pinned module is admitted and reports its digest, imports and exports" do
    bytes = real_bytes()
    assert {:ok, %{wasm_sha256: digest, imports: imports, exports: exports}} = EngineLoad.admit(bytes, [])
    assert digest == sha(bytes)

    if pin = EngineLoad.pinned_sha256(), do: assert(digest == pin)

    export_names = Enum.map(exports, &export_name/1)
    for required <- EngineLoad.required_exports(), do: assert(required in export_names)
    assert Enum.all?(imports, &(import_module(&1) == "wasi_snapshot_preview1"))
  end

  test "a wrong expected_sha256 is refused :wasm_digest_mismatch" do
    bytes = real_bytes()
    # positive control: the correct digest is admitted
    assert {:ok, _} = EngineLoad.admit(bytes, expected_sha256: sha(bytes))

    wrong = String.duplicate("0", 64)

    assert {:error, %Refusal{code: :wasm_digest_mismatch, class: :refused_identity, broken_term: :R_missing_identity}} =
             EngineLoad.admit(bytes, expected_sha256: wrong)
  end

  test "garbage bytes are refused :wasm_invalid" do
    assert {:ok, _} = EngineLoad.admit(real_bytes(), [])

    assert {:error, %Refusal{code: :wasm_invalid, class: :refused_structure}} =
             EngineLoad.admit("not a wasm module", expected_sha256: :unpinned)

    # under the pin the same bytes never reach the compiler: the digest is judged first
    assert {:error, %Refusal{code: :wasm_digest_mismatch}} = EngineLoad.admit("not a wasm module", [])
  end

  test "a foreign import surface is refused before instantiation" do
    assert {:ok, _} = EngineLoad.admit(real_bytes(), [])

    assert {:error, %Refusal{code: :wasm_import_surface_mismatch, class: :refused_identity}} =
             EngineLoad.admit(@foreign_import, expected_sha256: :unpinned)
  end

  test "a module without the required exports is refused :wasm_missing_export" do
    assert {:error, %Refusal{code: :wasm_missing_export, class: :refused_structure}} =
             EngineLoad.admit(@empty_module, expected_sha256: :unpinned)
  end

  describe "through a real Host" do
    defp start_raw_host(opts) do
      spec = Supervisor.child_spec({Host, Keyword.put_new(opts, :name, nil)}, id: make_ref())
      start_supervised!(spec)
    end

    test "a wrong expected_sha256 leaves a host that answers every call with the refusal" do
      # positive control
      good = start_raw_host(wasm_path: wasm_path())
      assert {:ok, %{"ok" => true}} = Host.request(good, %{"op" => "capabilities"})

      bad = start_raw_host(wasm_path: wasm_path(), expected_sha256: String.duplicate("0", 64))
      assert {:error, %Refusal{code: :wasm_digest_mismatch}} = Host.request(bad, %{"op" => "capabilities"})
      assert Process.alive?(bad)
    end

    test "an explicit non-vendored path is unpinned and accepted" do
      src = wasm_path()
      copy = Path.join(System.tmp_dir!(), "ash_graphlaw_unpinned_#{System.unique_integer([:positive])}.wasm")
      File.cp!(src, copy)
      on_exit(fn -> File.rm(copy) end)

      if Path.expand(copy) != Path.expand(WasmConfig.wasm_path([])) do
        assert WasmConfig.expected_sha256(wasm_path: copy) == :unpinned
      end

      host = start_raw_host(wasm_path: copy)
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities"})
    end

    test "a foreign module handed to a host never crashes the caller" do
      bytes = @foreign_import
      host = start_raw_host(bytes: bytes, expected_sha256: :unpinned)
      assert {:error, %Refusal{class: class}} = Host.request(host, %{"op" => "capabilities"})
      assert class in [:refused_identity, :refused_structure]
      assert Process.alive?(host)
    end
  end

  defp export_name({name, _}), do: to_string(name)
  defp export_name(%{name: name}), do: to_string(name)
  defp export_name(name), do: to_string(name)

  defp import_module({mod, _name, _}), do: to_string(mod)
  defp import_module({mod, _}), do: to_string(mod)
  defp import_module(%{module: mod}), do: to_string(mod)
  defp import_module(%{"module" => mod}), do: to_string(mod)
  defp import_module(mod) when is_binary(mod), do: mod
end
