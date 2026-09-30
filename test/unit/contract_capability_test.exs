# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.ContractCapabilityTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test of Contract capability checks.
  # Uses the real generated AshGraphLaw.Dsl.Capability struct and the real Registry; no doubles.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Contract

  defp cap(name, ceiling), do: struct!(AshGraphLaw.Dsl.Capability, name: name, ceiling: ceiling)
  defp compiled(entities), do: %{graphlaw: entities}

  describe "positive control" do
    test "valid capabilities with sufficient ceilings pass" do
      assert :ok = Contract.validate(compiled([cap(:sparql, :observe), cap(:shacl, :select), cap(:law, :construct)]))
    end

    test "existing payload_steps/0 is unchanged" do
      assert Contract.payload_steps() == [:shacl, :n3, :hooks, :plan, :require_receipt, :require_signed_receipt]
    end

    test "no capabilities is still :ok" do
      assert :ok = Contract.validate(compiled([]))
    end
  end

  describe "refusals" do
    test "unknown capability name" do
      assert {:error, [%{code: :unknown_capability, detail: detail}]} =
               Contract.validate(compiled([cap(:bogus, :construct)]))

      assert detail =~ "bogus"
    end

    test "ceiling below the op minimum" do
      assert {:error, [%{code: :ceiling_unmet, detail: detail}]} =
               Contract.validate(compiled([cap(:entail, :observe)]))

      assert detail =~ "entail"
    end

    test "select is still below construct" do
      assert {:error, [%{code: :ceiling_unmet}]} = Contract.validate(compiled([cap(:hooks, :select)]))
    end

    test "duplicate capability names" do
      assert {:error, [%{code: :duplicate_capability, detail: detail}]} =
               Contract.validate(compiled([cap(:sparql, :observe), cap(:sparql, :observe)]))

      assert detail =~ "sparql"
    end

    test "findings accumulate" do
      assert {:error, refusals} = Contract.validate(compiled([cap(:bogus, :observe), cap(:n3, :observe)]))
      assert Enum.map(refusals, & &1.code) |> Enum.sort() == [:ceiling_unmet, :unknown_capability]
    end
  end
end
