# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits negative courts.

defmodule AshGraphLaw.Negative.RefusalNegativeTest do
  @moduledoc """
  Negative court for the closed refusal table and the engine-payload mapping.

  The table below is the contract; the generated `AshGraphLaw.Refusal` must agree with it
  code for code. `from_engine/2` is fed hostile payloads (nil, lists, deep nesting, unknown
  kinds and codes) and must classify without ever raising.
  """

  use ExUnit.Case, async: true

  alias AshGraphLaw.Refusal

  @table [
    {:not_admitted, :refused_admission},
    {:plan_refused, :refused_admission},
    {:receipt_required, :refused_admission},
    {:lease_refused, :refused_authority},
    {:resource_limit, :blocked_resource},
    {:policy_refused, :refused_admission},
    {:engine_refused, :refused_structure},
    {:engine_unclassified, :unsupported},
    {:wasm_not_vendored, :blocked_resource},
    {:wasm_unreadable, :blocked_resource},
    {:wasm_invalid, :refused_structure},
    {:wasm_digest_mismatch, :refused_identity},
    {:wasm_import_surface_mismatch, :refused_identity},
    {:wasm_missing_export, :refused_structure},
    {:abi_version_mismatch, :refused_identity},
    {:instantiation_failed, :blocked_resource},
    {:abi_failure, :blocked_resource},
    {:call_trapped, :blocked_resource},
    {:call_exited, :blocked_resource},
    {:call_timeout, :blocked_resource},
    {:saturated, :blocked_resource},
    {:host_not_started, :blocked_resource},
    {:fuel_exhausted, :blocked_resource},
    {:invalid_encoding, :refused_structure},
    {:invalid_json, :refused_structure},
    {:malformed_response, :refused_structure},
    {:unknown_admission, :refused_structure},
    {:duplicate_admission, :refused_structure},
    {:missing_law_module, :refused_structure},
    {:invalid_runtime_option, :refused_structure},
    {:invalid_trusted_key, :refused_authority},
    {:ceiling_unmet, :refused_authority},
    {:projection_failed, :refused_structure},
    {:law_module_failed, :refused_structure},
    {:unsupported_step, :unsupported}
  ]

  @taxonomy [
    :mu_on_O,
    :admission_vacuous,
    :R_missing_identity,
    :R_missing_authority,
    :R_missing_consequence,
    :R_missing_replay,
    :R_missing_standing,
    :mu_unlawful
  ]

  defp nested(0), do: %{"kind" => "Leaf"}
  # One shared inner term per level: a naive double call is 2^n terms and turns nested(60) into a hang.
  defp nested(n) do
    inner = nested(n - 1)
    %{"details" => inner, "kind" => "K#{n}", "message" => [inner]}
  end

  describe "the closed table" do
    test "positive control: a known code builds a filled refusal" do
      refusal = Refusal.new(:not_admitted, "shape violated", %{violations: []})

      assert %Refusal{code: :not_admitted, class: :refused_admission, broken_term: :mu_on_O, message: "shape violated"} =
               refusal
    end

    test "the generated codes are exactly the contract codes" do
      assert Enum.sort(Refusal.codes()) == @table |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    end

    test "every code maps to its contract class and to a taxonomy term" do
      for {code, class} <- @table do
        assert Refusal.class_of(code) == class, "class of #{code}"
        assert Refusal.broken_term_of(code) in @taxonomy, "broken_term of #{code}"
        assert %Refusal{class: ^class} = Refusal.new(code, "m")
        assert Refusal.class_of(code) in Refusal.classes()
      end
    end

    test "the classes are exactly the closed six" do
      assert Enum.sort(Refusal.classes()) ==
               Enum.sort([
                 :refused_identity,
                 :refused_structure,
                 :refused_authority,
                 :refused_admission,
                 :blocked_resource,
                 :unsupported
               ])
    end

    test "identity, authority and admission codes witness the documented failure terms" do
      for code <- [:wasm_digest_mismatch, :wasm_import_surface_mismatch, :abi_version_mismatch],
          do: assert(Refusal.broken_term_of(code) == :R_missing_identity)

      for code <- [:lease_refused, :ceiling_unmet],
          do: assert(Refusal.broken_term_of(code) == :R_missing_authority)

      for code <- [:not_admitted, :plan_refused, :policy_refused, :receipt_required],
          do: assert(Refusal.broken_term_of(code) == :mu_on_O)
    end

    test "a code outside the closed table raises ArgumentError everywhere" do
      for bogus <- [:bogus, :NotAdmitted, nil, "not_admitted", 1] do
        assert_raise ArgumentError, fn -> Refusal.new(bogus, "x") end
        assert_raise ArgumentError, fn -> Refusal.class_of(bogus) end
        assert_raise ArgumentError, fn -> Refusal.broken_term_of(bogus) end
      end
    end
  end

  describe "from_engine/2" do
    test "positive control: each documented engine code maps to its refusal" do
      for {engine, code} <- [
            {"NotAdmitted", :not_admitted},
            {"PlanRefused", :plan_refused},
            {"ReceiptRequired", :receipt_required},
            {"LeaseRefused", :lease_refused},
            {"ResourceLimit", :resource_limit},
            {"PolicyRefused", :policy_refused}
          ] do
        assert %Refusal{code: ^code} = Refusal.from_engine(%{"kind" => "Refused", "details" => %{"code" => engine}})
      end
    end

    test "an engine kind without a detail code is :engine_refused and keeps the kind" do
      assert %Refusal{code: :engine_refused, kind: "EngineRejected"} =
               Refusal.from_engine(%{"kind" => "EngineRejected", "message" => "no"})
    end

    test "unknown future variants are :engine_unclassified, never a crash" do
      for payload <- [
            %{"kind" => "SomethingNew", "details" => %{"code" => "FutureCode"}},
            %{"details" => %{"code" => "notacode"}},
            %{"details" => %{"code" => 5}},
            %{"details" => %{"code" => nil}},
            %{"kind" => 5},
            %{}
          ] do
        assert %Refusal{code: :engine_unclassified, class: :unsupported} = Refusal.from_engine(payload)
      end
    end

    test "hostile payloads never raise and always yield a closed-table refusal" do
      payloads = [
        nil,
        [],
        [1, 2, 3],
        "a string",
        42,
        :atom,
        {:tuple, 1},
        %{"details" => nil},
        %{"details" => [1, 2]},
        %{"details" => "string", "kind" => ["list"]},
        %{"message" => %{"nested" => "map"}},
        %{"engine" => 1, "dialect" => [], "kind" => %{}},
        %{atom_key: "value"},
        nested(1),
        nested(60),
        Map.new(1..500, fn i -> {"k#{i}", i} end)
      ]

      for payload <- payloads, details <- [%{}, %{"code" => "NotAdmitted"}, nil, [], "s"] do
        refusal = Refusal.from_engine(payload, details)
        assert %Refusal{} = refusal
        assert refusal.code in Refusal.codes()
        assert refusal.class == Refusal.class_of(refusal.code)
        assert refusal.message != ""
      end
    end

    test "non-map input keeps a printable copy of the raw value in details" do
      assert %Refusal{code: :engine_unclassified, details: %{"raw" => raw}} = Refusal.from_engine([1, 2, 3])
      assert raw == inspect([1, 2, 3])
    end

    test "non-binary message, kind, engine and dialect fields are dropped, not propagated" do
      refusal = Refusal.from_engine(%{"kind" => "K", "message" => 5, "engine" => 6, "dialect" => 7})
      assert refusal.kind == "K"
      assert refusal.engine == nil
      assert refusal.dialect == nil
      # the non-binary message was dropped, so the message is the code's documented default
      assert refusal.message == Refusal.doc_of(refusal.code)
    end
  end
end
