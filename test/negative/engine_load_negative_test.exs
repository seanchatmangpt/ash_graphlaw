# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits negative courts.

defmodule AshGraphLaw.Negative.EngineLoadNegativeTest do
  @moduledoc """
  Negative court for the engine load boundary.

  Foreign modules are REAL wasm binaries assembled by `AshGraphLaw.Test.WasmFixtures` and
  compiled by the real wasmtime through `AshGraphLaw.EngineLoad`. Each refusal has a
  positive control on the same fixture family (an admissible surface is admitted), and the
  real pinned engine is the control under `:wasm`.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.{EngineLoad, Refusal}
  alias AshGraphLaw.Test.WasmFixtures

  setup do
    EngineLoad.purge_cache()
    on_exit(&EngineLoad.purge_cache/0)
    :ok
  end

  test "positive control: an admissible surface with the exact digest is admitted" do
    bytes = WasmFixtures.admissible_surface()
    digest = WasmFixtures.sha256(bytes)

    assert {:ok, %{wasm_sha256: ^digest, exports: exports}} = EngineLoad.admit(bytes, expected_sha256: digest)
    for name <- EngineLoad.required_exports(), do: assert(Map.has_key?(exports, name))
  end

  test "a foreign import module is refused and named" do
    bytes = WasmFixtures.foreign_imports()

    assert {:error, %Refusal{code: :wasm_import_surface_mismatch, class: :refused_identity} = refusal} =
             EngineLoad.admit(bytes, expected_sha256: :unpinned)

    assert refusal.details.unexpected == ["env"]
    refute EngineLoad.cached?(WasmFixtures.sha256(bytes))
  end

  test "a pin mismatch is judged before the import surface: the foreign module is never compiled" do
    bytes = WasmFixtures.foreign_imports()
    wrong = String.duplicate("0", 64)

    # positive control: the same bytes reach the surface diagnosis once the pin is their own digest
    assert {:error, %Refusal{code: :wasm_import_surface_mismatch}} =
             EngineLoad.admit(bytes, expected_sha256: WasmFixtures.sha256(bytes))

    assert {:error, %Refusal{code: :wasm_digest_mismatch, details: %{expected: ^wrong}}} =
             EngineLoad.admit(bytes, expected_sha256: wrong)
  end

  test "WASI functions outside the manifest allowlist are refused by name, module-level checks notwithstanding" do
    assert {:ok, _} = EngineLoad.admit(WasmFixtures.admissible_surface(), expected_sha256: :unpinned)

    for {bytes, offender} <- [
          {WasmFixtures.forbidden_wasi_import(), "wasi_snapshot_preview1.path_open"},
          {WasmFixtures.wrong_type_wasi_import(), "wasi_snapshot_preview1.fd_write"}
        ] do
      assert {:error, %Refusal{code: :wasm_import_surface_mismatch} = refusal} =
               EngineLoad.admit(bytes, expected_sha256: :unpinned)

      assert offender in refusal.details.unexpected_functions
      refute EngineLoad.cached?(WasmFixtures.sha256(bytes))
    end
  end

  test "a missing gl_call export is refused" do
    good = WasmFixtures.admissible_surface()
    assert {:ok, _} = EngineLoad.admit(good, expected_sha256: :unpinned)

    bytes = WasmFixtures.build([{"wasi_snapshot_preview1", "proc_exit"}], ["gl_alloc", "gl_free", "memory"])

    assert {:error, %Refusal{code: :wasm_missing_export, class: :refused_structure} = refusal} =
             EngineLoad.admit(bytes, expected_sha256: :unpinned)

    assert refusal.details.missing == ["gl_call"]
  end

  test "missing exports are all reported, and a partial set is not admitted" do
    assert {:error, %Refusal{code: :wasm_missing_export, details: %{missing: missing}}} =
             EngineLoad.admit(WasmFixtures.missing_exports(), expected_sha256: :unpinned)

    assert missing == ["gl_alloc", "gl_call", "gl_free"]

    assert {:error, %Refusal{code: :wasm_missing_export, details: %{missing: ["gl_free"]}}} =
             EngineLoad.admit(WasmFixtures.missing_gl_free(), expected_sha256: :unpinned)
  end

  test "garbage and non-binary input is refused as wasm_invalid, never raised" do
    assert {:ok, _} = EngineLoad.admit(WasmFixtures.admissible_surface(), expected_sha256: :unpinned)

    for junk <- [WasmFixtures.not_wasm(), <<>>, <<0, 97, 115, 109>>, <<0, 97, 115, 109, 1, 0, 0, 0, 255>>] do
      assert {:error, %Refusal{code: :wasm_invalid, class: :refused_structure}} =
               EngineLoad.admit(junk, expected_sha256: :unpinned)
    end

    for not_binary <- [nil, :atom, 42, [1, 2], %{}] do
      assert {:error, %Refusal{code: :wasm_invalid}} = EngineLoad.admit(not_binary, [])
    end
  end

  test "a wrong digest is refused with both digests reported, and the module is not cached" do
    bytes = WasmFixtures.admissible_surface()
    digest = WasmFixtures.sha256(bytes)
    wrong = String.duplicate("a", 64)

    # control: the right pin admits
    assert {:ok, _} = EngineLoad.admit(bytes, expected_sha256: digest)
    EngineLoad.purge_cache()

    assert {:error, %Refusal{code: :wasm_digest_mismatch, class: :refused_identity} = refusal} =
             EngineLoad.admit(bytes, expected_sha256: wrong)

    assert refusal.details.expected == wrong
    assert refusal.details.actual == digest
    refute EngineLoad.cached?(digest)
  end

  test "a cached admission does not bypass a later, different pin" do
    bytes = WasmFixtures.admissible_surface()
    digest = WasmFixtures.sha256(bytes)

    assert {:ok, _} = EngineLoad.admit(bytes, expected_sha256: digest)
    assert EngineLoad.cached?(digest)

    assert {:error, %Refusal{code: :wasm_digest_mismatch}} =
             EngineLoad.admit(bytes, expected_sha256: String.duplicate("b", 64))
  end

  test "a nil pin (manifest unusable) never admits by default" do
    bytes = WasmFixtures.admissible_surface()
    digest = WasmFixtures.sha256(bytes)
    assert {:ok, _} = EngineLoad.admit(bytes, expected_sha256: digest)
    EngineLoad.purge_cache()

    assert {:error, %Refusal{code: :wasm_digest_mismatch}} = EngineLoad.admit(bytes, expected_sha256: nil)
  end

  @tag :wasm
  test "the real pinned engine is admitted; the same bytes with a wrong pin are not" do
    bytes = File.read!(wasm_path())
    assert {:ok, %{wasm_sha256: digest}} = EngineLoad.admit(bytes, [])
    assert digest == EngineLoad.pinned_sha256()

    EngineLoad.purge_cache()

    assert {:error, %Refusal{code: :wasm_digest_mismatch}} =
             EngineLoad.admit(bytes, expected_sha256: String.duplicate("c", 64))
  end
end
