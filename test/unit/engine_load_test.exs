# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.EngineLoadTest do
  # async: false -- the telemetry test attaches to a node-global event and must not see
  # admissions from concurrently running modules.
  use ExUnit.Case, async: false

  alias AshGraphLaw.EngineLoad
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Test.WasmFixtures

  @event [:ash_graphlaw, :engine, :admit]

  @doc false
  def forward(event, measurements, metadata, pid), do: send(pid, {:telemetry, event, measurements, metadata})

  defp attach! do
    id = "engine-load-test-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(id, @event, &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
  end

  describe "required_exports/0 and pinned_sha256/0" do
    test "the engine must export gl_alloc, gl_call, gl_free and memory" do
      assert EngineLoad.required_exports() |> Enum.map(&to_string/1) |> Enum.sort() ==
               ~w(gl_alloc gl_call gl_free memory)
    end

    test "the pin is the GraphLaw v26.9.29 release asset digest (literal control)" do
      assert EngineLoad.pinned_sha256() == "7bb2a7e5ebcef7584b0b960451272d56fa75414d76a12138d41e8973e126eee0"
    end

    test "the pin equals the sha256 recorded in the shipped MANIFEST.json" do
      manifest = "priv/graphlaw/MANIFEST.json" |> File.read!() |> Jason.decode!()
      assert EngineLoad.pinned_sha256() == manifest["artifact"]["sha256"]
      assert manifest["artifact"]["url"] =~ "/releases/download/v#{manifest["graphlaw_version"]}/"
    end
  end

  describe "admit/2 with a structurally admissible module" do
    test "positive control: correct surface and matching digest is admitted" do
      bytes = WasmFixtures.admissible_surface()
      sha = WasmFixtures.sha256(bytes)

      assert {:ok, %{wasm_sha256: ^sha, imports: imports, exports: exports}} =
               EngineLoad.admit(bytes, expected_sha256: sha)

      assert inspect(imports) =~ "proc_exit"

      for required <- ~w(gl_alloc gl_call gl_free memory) do
        assert inspect(exports) =~ required
      end
    end

    test "the same module with a wrong expected digest is refused :wasm_digest_mismatch" do
      bytes = WasmFixtures.admissible_surface()

      assert {:error, %Refusal{code: :wasm_digest_mismatch} = refusal} =
               EngineLoad.admit(bytes, expected_sha256: String.duplicate("0", 64))

      assert refusal.class == :refused_identity
      assert refusal.broken_term == :R_missing_identity
    end

    test "with default options the pin applies, so a foreign-but-well-formed module is refused" do
      assert {:error, %Refusal{code: :wasm_digest_mismatch}} = EngineLoad.admit(WasmFixtures.admissible_surface(), [])
    end
  end

  # With `expected_sha256: :unpinned` the caller chose the bytes, so the structural diagnosis is the
  # only gate left: compile, import allowlist (module, name AND type), exports, in that order.
  describe "admit/2 structural refusals (unpinned: the caller chose the bytes)" do
    @unpinned [expected_sha256: :unpinned]

    test "positive control: the admissible surface passes every structural gate" do
      assert {:ok, %{wasm_sha256: sha}} = EngineLoad.admit(WasmFixtures.admissible_surface(), @unpinned)
      assert sha == WasmFixtures.sha256(WasmFixtures.admissible_surface())
    end

    test "bytes that are not WebAssembly are refused :wasm_invalid" do
      assert {:error, %Refusal{code: :wasm_invalid, class: :refused_structure}} =
               EngineLoad.admit(WasmFixtures.not_wasm(), @unpinned)
    end

    test "an empty binary is refused :wasm_invalid" do
      assert {:error, %Refusal{code: :wasm_invalid}} = EngineLoad.admit(<<>>, @unpinned)
    end

    test "a truncated module is refused :wasm_invalid" do
      truncated = binary_part(WasmFixtures.admissible_surface(), 0, 20)
      assert {:error, %Refusal{code: :wasm_invalid}} = EngineLoad.admit(truncated, @unpinned)
    end

    test "a module importing from a foreign module is refused :wasm_import_surface_mismatch" do
      assert {:error, %Refusal{code: :wasm_import_surface_mismatch, class: :refused_identity} = refusal} =
               EngineLoad.admit(WasmFixtures.foreign_imports(), @unpinned)

      assert refusal.details.unexpected == ["env"]
    end

    test "a WASI function outside the allowlist is refused and named" do
      assert {:error, %Refusal{code: :wasm_import_surface_mismatch} = refusal} =
               EngineLoad.admit(WasmFixtures.forbidden_wasi_import(), @unpinned)

      assert refusal.details.unexpected == []
      assert refusal.details.unexpected_functions == ["wasi_snapshot_preview1.path_open"]
      refute "path_open" in refusal.details.allowed_functions
      assert "fd_write" in refusal.details.allowed_functions
    end

    test "an allowlisted WASI name with the wrong type is refused (types are checked, not just names)" do
      assert {:error, %Refusal{code: :wasm_import_surface_mismatch} = refusal} =
               EngineLoad.admit(WasmFixtures.wrong_type_wasi_import(), @unpinned)

      assert refusal.details.unexpected_functions == ["wasi_snapshot_preview1.fd_write"]
    end

    test "a module missing every gl_* export is refused :wasm_missing_export" do
      assert {:error, %Refusal{code: :wasm_missing_export, class: :refused_structure}} =
               EngineLoad.admit(WasmFixtures.missing_exports(), @unpinned)
    end

    test "a module missing only gl_free is refused :wasm_missing_export" do
      assert {:error, %Refusal{code: :wasm_missing_export}} =
               EngineLoad.admit(WasmFixtures.missing_gl_free(), @unpinned)
    end

    test "the import surface is judged before exports" do
      bytes = WasmFixtures.foreign_imports()
      assert {:error, %Refusal{code: :wasm_import_surface_mismatch}} = EngineLoad.admit(bytes, @unpinned)
    end
  end

  describe "admit/2 pinned loads judge the digest BEFORE compiling untrusted bytes" do
    test "positive control: the same bytes are admitted once their own digest is the pin" do
      bytes = WasmFixtures.admissible_surface()
      assert {:ok, _} = EngineLoad.admit(bytes, expected_sha256: WasmFixtures.sha256(bytes))
    end

    test "bytes that would not even compile are refused :wasm_digest_mismatch, proving compile never ran" do
      assert {:error, %Refusal{code: :wasm_digest_mismatch, class: :refused_identity}} =
               EngineLoad.admit(WasmFixtures.not_wasm(), [])

      assert {:error, %Refusal{code: :wasm_digest_mismatch}} =
               EngineLoad.admit(WasmFixtures.not_wasm(), expected_sha256: String.duplicate("0", 64))
    end

    test "a foreign surface under a pin that does not match is a digest mismatch, not a surface diagnosis" do
      for bytes <- [
            WasmFixtures.foreign_imports(),
            WasmFixtures.missing_exports(),
            WasmFixtures.forbidden_wasi_import()
          ] do
        assert {:error, %Refusal{code: :wasm_digest_mismatch}} =
                 EngineLoad.admit(bytes, expected_sha256: String.duplicate("0", 64))
      end
    end

    test "a pinned load whose digest matches still fails the structural gates" do
      bytes = WasmFixtures.foreign_imports()

      assert {:error, %Refusal{code: :wasm_import_surface_mismatch}} =
               EngineLoad.admit(bytes, expected_sha256: WasmFixtures.sha256(bytes))
    end

    test "a nil pin (unusable manifest) is a refusal, never unpinned" do
      assert {:error, %Refusal{code: :wasm_digest_mismatch}} =
               EngineLoad.admit(WasmFixtures.admissible_surface(), expected_sha256: nil)
    end

    test "a foreign module cannot crash the caller: refusal is a value, not an exit" do
      for bytes <- [WasmFixtures.foreign_imports(), WasmFixtures.not_wasm(), WasmFixtures.missing_exports()] do
        assert {:error, %Refusal{}} = EngineLoad.admit(bytes, [])
      end

      assert Process.alive?(self())
    end
  end

  describe "telemetry [:ash_graphlaw, :engine, :admit]" do
    test "an admitted module emits an event carrying its digest" do
      attach!()
      bytes = WasmFixtures.admissible_surface()
      sha = WasmFixtures.sha256(bytes)

      assert {:ok, _} = EngineLoad.admit(bytes, expected_sha256: sha)
      assert_receive {:telemetry, @event, _measurements, %{wasm_sha256: ^sha} = metadata}, 1_000
      refute Map.get(metadata, :code)
    end

    test "a refused module emits an event carrying the typed code" do
      attach!()

      assert {:error, %Refusal{code: :wasm_import_surface_mismatch}} =
               EngineLoad.admit(WasmFixtures.foreign_imports(), expected_sha256: :unpinned)

      assert_receive {:telemetry, @event, _measurements, %{code: :wasm_import_surface_mismatch}}, 1_000
    end
  end

  describe "the real vendored engine" do
    @describetag :wasm

    test "positive control: the pinned engine passes the whole gate" do
      bytes = File.read!(AshGraphLaw.WasmConfig.wasm_path([]))
      pin = EngineLoad.pinned_sha256()

      assert {:ok, %{wasm_sha256: ^pin, exports: exports}} = EngineLoad.admit(bytes, [])

      for required <- ~w(gl_alloc gl_call gl_free memory) do
        assert inspect(exports) =~ required
      end
    end

    test "the same real bytes are refused when the expected digest is wrong" do
      bytes = File.read!(AshGraphLaw.WasmConfig.wasm_path([]))

      assert {:error, %Refusal{code: :wasm_digest_mismatch}} =
               EngineLoad.admit(bytes, expected_sha256: String.duplicate("f", 64))
    end

    test "a single flipped byte in the real engine is refused, never admitted as the pinned engine" do
      bytes = File.read!(AshGraphLaw.WasmConfig.wasm_path([]))
      last = byte_size(bytes) - 1
      <<head::binary-size(last), byte>> = bytes
      tampered = head <> <<Bitwise.bxor(byte, 0xFF)>>

      assert {:error, %Refusal{code: code}} = EngineLoad.admit(tampered, [])
      assert code in [:wasm_invalid, :wasm_import_surface_mismatch, :wasm_missing_export, :wasm_digest_mismatch]
    end
  end
end
