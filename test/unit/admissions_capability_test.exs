# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.AdmissionsCapabilityTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test of Admissions capability reads.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Refusal

  defmodule Dom do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshGraphLaw.AdmissionsCapabilityTest.Declared
      resource AshGraphLaw.AdmissionsCapabilityTest.Undeclared
    end
  end

  defmodule Declared do
    @moduledoc false
    use Ash.Resource,
      domain: AshGraphLaw.AdmissionsCapabilityTest.Dom,
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
      capability(:shacl, ceiling: :select)
      admission(:observed, step: :rdfs, ceiling: :observe)
    end
  end

  defmodule Undeclared do
    @moduledoc false
    use Ash.Resource,
      domain: AshGraphLaw.AdmissionsCapabilityTest.Dom,
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

  describe "capabilities/1" do
    test "positive control: lists declared capabilities in declaration order" do
      assert [sparql, shacl] = Admissions.capabilities(Declared)
      assert {sparql.name, sparql.ceiling} == {:sparql, :observe}
      assert {shacl.name, shacl.ceiling} == {:shacl, :select}
    end

    test "a resource declaring none has none" do
      assert Admissions.capabilities(Undeclared) == []
    end

    test "a module without the extension has none" do
      assert Admissions.capabilities(String) == []
    end

    test "admissions are untouched by capabilities" do
      assert [%{name: :observed}] = Admissions.all(Declared)
    end
  end

  describe "capability/2 and declared?/2" do
    test "positive control: fetches by atom or string" do
      assert {:ok, %{name: :sparql}} = Admissions.capability(Declared, :sparql)
      assert {:ok, %{name: :shacl}} = Admissions.capability(Declared, "shacl")
      assert Admissions.declared?(Declared, :sparql)
    end

    test "an undeclared name is a typed refusal listing the known names" do
      assert {:error, %Refusal{code: :capability_not_declared, details: details}} =
               Admissions.capability(Declared, :entail)

      assert details.known == ["sparql", "shacl"]
      refute Admissions.declared?(Declared, :entail)
    end

    test "nothing is declared on a resource without capabilities" do
      refute Admissions.declared?(Undeclared, :sparql)
    end
  end
end
