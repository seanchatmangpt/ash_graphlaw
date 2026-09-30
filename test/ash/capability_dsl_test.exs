# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Ash.CapabilityDslTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test of the capability DSL entity
  # and the Authority.check_op/3 boundary against real Ash resources.
  use ExUnit.Case, async: true

  alias AshGraphLaw.{Admissions, Authority, Refusal}

  defmodule Dom do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshGraphLaw.Ash.CapabilityDslTest.Scoped
      resource AshGraphLaw.Ash.CapabilityDslTest.Open
    end
  end

  defmodule Scoped do
    @moduledoc false
    use Ash.Resource,
      domain: AshGraphLaw.Ash.CapabilityDslTest.Dom,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshGraphLaw.Resource]

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end

    graphlaw do
      capability(:sparql)
      capability(:shacl)
      capability(:law, ceiling: :construct)
    end
  end

  defmodule Open do
    @moduledoc false
    use Ash.Resource,
      domain: AshGraphLaw.Ash.CapabilityDslTest.Dom,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshGraphLaw.Resource]

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end

    graphlaw do
      admission(:observed, step: :rdfs, ceiling: :observe)
    end
  end

  @signed %{"lease" => %{"ceiling" => "construct"}, "attestation" => %{}}

  describe "positive control" do
    test "a resource with capability :sparql and :shacl compiles and lists them in order" do
      assert Ash.Resource.Info.resource?(Scoped)
      assert Scoped |> Admissions.capabilities() |> Enum.map(& &1.name) == [:sparql, :shacl, :law]
    end

    test "declared ops pass check_op/3" do
      assert :ok = Authority.check_op(Scoped, :sparql)
      assert :ok = Authority.check_op(Scoped, "shacl")
    end

    test "a declared construct capability accepts a construct lease" do
      assert :ok = Authority.check_op(Scoped, :law, lease: %{signed_lease: @signed})
    end
  end

  describe "check_op/3 negatives" do
    test "an undeclared op is refused :capability_not_declared" do
      assert {:error, %Refusal{code: :capability_not_declared}} = Authority.check_op(Scoped, :entail)
    end

    test "an unknown op is refused :unknown_capability" do
      assert {:error, %Refusal{code: :unknown_capability}} = Authority.check_op(Scoped, :frobnicate)
      assert {:error, %Refusal{code: :unknown_capability}} = Authority.check_op(Open, :frobnicate)
    end

    test "a construct capability without a signed lease is :ceiling_unmet" do
      assert {:error, %Refusal{code: :ceiling_unmet}} = Authority.check_op(Scoped, :law, lease: nil)
      assert {:error, %Refusal{code: :ceiling_unmet}} = Authority.check_op(Scoped, :law, lease: %{ceiling: :construct})
    end
  end

  describe "resource declaring none allows all" do
    test "every registry op passes" do
      for op <- ~w(capabilities sniff parse convert canonical sparql shacl shex n3 entail datalog hooks law policy) do
        assert :ok = Authority.check_op(Open, op)
      end
    end
  end

  describe "op_ceiling/1" do
    test "observe ops" do
      for op <- ~w(capabilities sniff parse convert canonical sparql shacl shex policy) do
        assert {:ok, :observe} = Authority.op_ceiling(op)
      end
    end

    test "construct ops, atom or string" do
      for op <- ~w(n3 entail datalog hooks law) do
        assert {:ok, :construct} = Authority.op_ceiling(op)
        assert {:ok, :construct} = Authority.op_ceiling(String.to_atom(op))
      end
    end

    test "unknown op" do
      assert {:error, %Refusal{code: :unknown_capability}} = Authority.op_ceiling("nope")
      assert {:error, %Refusal{code: :unknown_capability}} = Authority.op_ceiling(42)
    end
  end
end
