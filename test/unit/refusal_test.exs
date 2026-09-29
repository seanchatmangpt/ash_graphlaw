# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.RefusalTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Refusal

  # The closed code table from the shared contract (section 2), written out independently of
  # the generated module so a drift between ontology and contract is caught here.
  @table [
    # engine
    {:not_admitted, :refused_admission},
    {:plan_refused, :refused_admission},
    {:receipt_required, :refused_admission},
    {:lease_refused, :refused_authority},
    {:resource_limit, :blocked_resource},
    {:policy_refused, :refused_admission},
    {:engine_refused, :refused_structure},
    {:engine_unclassified, :unsupported},
    # host
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
    # ash
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

  @classes [
    :refused_identity,
    :refused_structure,
    :refused_authority,
    :refused_admission,
    :blocked_resource,
    :unsupported
  ]
  @broken_terms [
    :mu_on_O,
    :admission_vacuous,
    :R_missing_identity,
    :R_missing_authority,
    :R_missing_consequence,
    :R_missing_replay,
    :R_missing_standing,
    :mu_unlawful
  ]

  describe "the closed code table" do
    test "the contract table has exactly 35 codes" do
      assert length(@table) == 35
      assert @table |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 35
    end

    test "codes/0 is exactly the contract's 35 codes, no more and no fewer" do
      assert Refusal.codes() |> Enum.sort() == @table |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    end

    for {code, class} <- @table do
      test "#{code} round-trips class #{class} and a closed broken_term through class_of/1, broken_term_of/1 and new/3" do
        code = unquote(code)
        class = unquote(class)

        assert Refusal.class_of(code) == class
        assert Refusal.broken_term_of(code) in @broken_terms

        refusal = Refusal.new(code, "message for #{code}", %{"k" => "v"})
        assert %Refusal{code: ^code, class: ^class} = refusal
        assert refusal.broken_term == Refusal.broken_term_of(code)
        assert refusal.message == "message for #{code}"
        assert refusal.class in @classes
      end
    end

    test "every class in the table belongs to the closed class set" do
      assert Enum.all?(@table, fn {_code, class} -> class in @classes end)
    end

    test "the Chatman broken_term assignments stated in the contract hold" do
      for code <- [:wasm_digest_mismatch, :wasm_import_surface_mismatch, :abi_version_mismatch] do
        assert Refusal.broken_term_of(code) == :R_missing_identity, inspect(code)
      end

      for code <- [:lease_refused, :ceiling_unmet] do
        assert Refusal.broken_term_of(code) == :R_missing_authority, inspect(code)
      end

      for code <- [:not_admitted, :plan_refused, :policy_refused, :receipt_required] do
        assert Refusal.broken_term_of(code) == :mu_on_O, inspect(code)
      end
    end
  end

  describe "exception behaviour" do
    test "a Refusal is raisable and carries its typed code through rescue" do
      refusal = Refusal.new(:saturated, "queue full")

      error =
        try do
          raise refusal
        rescue
          e in Refusal -> e
        end

      assert error.code == :saturated
      assert error.class == :blocked_resource
      assert Exception.message(error) =~ "queue full"
    end

    test "new/2 defaults details to an empty map" do
      assert %Refusal{details: details} = Refusal.new(:host_not_started, "down")
      assert details == %{}
    end
  end

  describe "from_engine/2 (engine refusal -> typed code)" do
    defp engine_error(details_code, kind \\ "Refused", message \\ "engine said no") do
      base = %{"kind" => kind, "engine" => nil, "dialect" => nil, "message" => message}
      if details_code, do: Map.put(base, "details", %{"code" => details_code, "kind" => kind}), else: base
    end

    test "positive control: NotAdmitted -> :not_admitted with the engine message preserved" do
      assert %Refusal{code: :not_admitted, class: :refused_admission, message: "admission refused"} =
               Refusal.from_engine(engine_error("NotAdmitted", "Refused", "admission refused"))
    end

    for {details_code, code} <- [
          {"NotAdmitted", :not_admitted},
          {"PlanRefused", :plan_refused},
          {"ReceiptRequired", :receipt_required},
          {"LeaseRefused", :lease_refused},
          {"ResourceLimit", :resource_limit},
          {"PolicyRefused", :policy_refused}
        ] do
      test "details.code #{details_code} maps to #{code} with the table's class and broken_term" do
        code = unquote(code)
        refusal = Refusal.from_engine(engine_error(unquote(details_code)))

        assert refusal.code == code
        assert refusal.class == Refusal.class_of(code)
        assert refusal.broken_term == Refusal.broken_term_of(code)
      end
    end

    test "details given as the second argument are honoured the same as embedded details" do
      error = engine_error(nil)
      refusal = Refusal.from_engine(error, %{"code" => "PlanRefused", "index" => 1})
      assert refusal.code == :plan_refused
    end

    test "details.code Refused falls back to the engine kind -> :engine_refused" do
      refusal = Refusal.from_engine(engine_error("Refused", "EngineRejected"))
      assert refusal.code == :engine_refused
      assert refusal.class == :refused_structure
    end

    for kind <- ~w(NotSemanticContent Ambiguous EngineRejected Unsupported) do
      test "a details-free engine kind #{kind} maps to :engine_refused" do
        assert %Refusal{code: :engine_refused} = Refusal.from_engine(engine_error(nil, unquote(kind)))
      end
    end

    test "an unknown future engine kind maps to :engine_unclassified and never crashes" do
      refusal = Refusal.from_engine(engine_error(nil, "SomeVariantAddedInAFutureGraphLaw"))

      assert refusal.code == :engine_unclassified
      assert refusal.class == :unsupported
      assert refusal.broken_term in @broken_terms
    end

    test "an unknown future details.code with an unknown kind is :engine_unclassified" do
      assert %Refusal{code: :engine_unclassified} =
               Refusal.from_engine(engine_error("QuantumRefusal", "AlsoNewKind"))
    end
  end
end
