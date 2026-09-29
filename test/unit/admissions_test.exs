# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.AdmissionsTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Dsl.Admission
  alias AshGraphLaw.Dsl.Runtime
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Test.Bare
  alias AshGraphLaw.Test.PlanLaw
  alias AshGraphLaw.Test.ShapeLaw
  alias AshGraphLaw.Test.Ticket

  describe "all/1" do
    test "positive control: lists the admissions declared on the resource" do
      assert [%Admission{}, %Admission{}] = admissions = Admissions.all(Ticket)
      assert admissions |> Enum.map(& &1.name) |> Enum.sort() == [:ticket_close, :ticket_shape]
    end

    test "a resource that declares no admissions has none" do
      assert Admissions.all(Bare) == []
    end
  end

  describe "fetch/2" do
    test "positive control: fetches a declared SHACL admission with its defaults" do
      assert {:ok, %Admission{} = admission} = Admissions.fetch(Ticket, :ticket_shape)

      assert admission.name == :ticket_shape
      assert admission.step == :shacl
      assert admission.ceiling == :construct
      assert admission.law == ShapeLaw
      assert admission.projection == nil
    end

    test "fetches a declared plan admission with its explicit :select ceiling" do
      assert {:ok, %Admission{} = admission} = Admissions.fetch(Ticket, :ticket_close)

      assert admission.step == :plan
      assert admission.ceiling == :select
      assert admission.law == PlanLaw
    end

    test "an undeclared name is refused as :unknown_admission" do
      assert {:error, %Refusal{code: :unknown_admission, class: :refused_structure}} =
               Admissions.fetch(Ticket, :no_such_admission)
    end

    test "a resource with no admissions refuses every name as :unknown_admission" do
      assert {:error, %Refusal{code: :unknown_admission}} = Admissions.fetch(Bare, :ticket_shape)
    end
  end

  describe "runtime/1" do
    test "positive control: returns the declared runtime section" do
      assert %Runtime{timeout_ms: 5000} = Admissions.runtime(Ticket)
    end

    test "undeclared runtime fields keep their struct defaults" do
      runtime = Admissions.runtime(Ticket)

      assert runtime.max_skew_secs == 60
      assert runtime.trusted_keys == [AshGraphLaw.Test.Lease.public_key_hex(:trusted)]
      assert runtime.wasm_path == nil
    end

    test "a resource whose section omits runtime gets the full struct defaults" do
      runtime = Admissions.runtime(Bare)

      assert %Runtime{} = runtime
      assert runtime.timeout_ms == 5000
      assert runtime.max_skew_secs == 60
      assert runtime.trusted_keys == []
      assert runtime.wasm_path == nil
    end
  end
end
