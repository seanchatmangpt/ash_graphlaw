# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Compat.DslFixtures.AnyLaw do
  @moduledoc false
  # UNSUPPORTED(generator-capability): inline law fixture; steps are never sent to an engine here.
  @behaviour AshGraphLaw.Law

  @impl true
  def steps(_subject, _admission), do: []
end

defmodule AshGraphLaw.Compat.DslFixtures.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Compat.DslFixtures.AllSteps
    resource AshGraphLaw.Compat.DslFixtures.NoCapabilities
  end
end

defmodule AshGraphLaw.Compat.DslFixtures.AllSteps do
  @moduledoc false
  # A resource using the pre-capability `:admission` DSL with every one of the 8 step atoms.
  use Ash.Resource,
    domain: AshGraphLaw.Compat.DslFixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  alias AshGraphLaw.Compat.DslFixtures.AnyLaw

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end

  graphlaw do
    runtime do
      timeout_ms(7000)
    end

    admission(:a_shacl, step: :shacl, ceiling: :observe, law: AnyLaw)
    admission(:a_n3, step: :n3, ceiling: :construct, law: AnyLaw)
    admission(:a_rdfs, step: :rdfs, ceiling: :construct)
    admission(:a_owl_rl, step: :owl_rl, ceiling: :construct)
    admission(:a_hooks, step: :hooks, ceiling: :construct, law: AnyLaw)
    admission(:a_plan, step: :plan, ceiling: :select, law: AnyLaw)
    admission(:a_require_receipt, step: :require_receipt, ceiling: :observe, law: AnyLaw)
    admission(:a_require_signed_receipt, step: :require_signed_receipt, ceiling: :observe, law: AnyLaw)
  end
end

defmodule AshGraphLaw.Compat.DslFixtures.NoCapabilities do
  @moduledoc false
  # Declares admissions and NO capability entity: must behave exactly as before capabilities existed.
  use Ash.Resource,
    domain: AshGraphLaw.Compat.DslFixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, create: []]
  end

  graphlaw do
    admission(:observed, step: :rdfs, ceiling: :observe)
  end
end

defmodule AshGraphLaw.Compat.AdmissionDslCompatTest do
  @moduledoc """
  The existing `:admission` DSL is untouched by the `capability` entity: a resource using all 8 step
  atoms still compiles and reads back through `AshGraphLaw.Admissions`, and a resource with no
  capability entities reports none and keeps its admissions and runtime defaults. Pure compile and
  read tests: no engine is called.

  UNSUPPORTED(generator-capability): hand-written Chicago test.
  """

  use ExUnit.Case, async: true

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Compat.DslFixtures.{AllSteps, NoCapabilities}
  alias AshGraphLaw.Dsl.{Admission, Runtime}

  @steps [:shacl, :n3, :rdfs, :owl_rl, :hooks, :plan, :require_receipt, :require_signed_receipt]

  describe "all 8 step atoms" do
    test "positive control: the fixture compiled as an Ash resource carrying the extension" do
      assert Ash.Resource.Info.resource?(AllSteps)
      assert AshGraphLaw.Resource in Spark.extensions(AllSteps)
    end

    test "every step atom is accepted and read back in declaration order" do
      admissions = Admissions.all(AllSteps)
      assert Enum.all?(admissions, &match?(%Admission{}, &1))
      assert Enum.map(admissions, & &1.step) == @steps

      assert Enum.map(admissions, & &1.name) ==
               [:a_shacl, :a_n3, :a_rdfs, :a_owl_rl, :a_hooks, :a_plan, :a_require_receipt, :a_require_signed_receipt]
    end

    test "declared ceilings and law modules are preserved per admission" do
      {:ok, plan} = Admissions.fetch(AllSteps, :a_plan)
      assert plan.ceiling == :select
      assert plan.law == AshGraphLaw.Compat.DslFixtures.AnyLaw

      {:ok, rdfs} = Admissions.fetch(AllSteps, :a_rdfs)
      assert rdfs.ceiling == :construct
      assert rdfs.law == nil

      {:ok, shacl} = Admissions.fetch(AllSteps, :a_shacl)
      assert shacl.ceiling == :observe
    end

    test "the runtime section keeps its declared value" do
      assert %Runtime{timeout_ms: 7000} = Admissions.runtime(AllSteps)
    end

    test "an unknown admission name is still a typed :unknown_admission refusal listing the known names" do
      assert {:ok, _} = Admissions.fetch(AllSteps, :a_shacl)

      assert {:error, %AshGraphLaw.Refusal{code: :unknown_admission, details: details}} =
               Admissions.fetch(AllSteps, :nope)

      assert details.known == Enum.map(Admissions.all(AllSteps), & &1.name)
    end
  end

  describe "a resource with no capability entities" do
    test "positive control: its admission is declared and readable" do
      assert [%Admission{name: :observed, step: :rdfs, ceiling: :observe}] = Admissions.all(NoCapabilities)
    end

    test "it declares no capabilities and no capability is 'declared'" do
      assert Admissions.capabilities(NoCapabilities) == []
      refute Admissions.declared?(NoCapabilities, :sparql)

      assert {:error, %AshGraphLaw.Refusal{code: :capability_not_declared}} =
               Admissions.capability(NoCapabilities, :sparql)
    end

    test "the runtime section falls back to the Dsl.Runtime struct defaults" do
      assert Admissions.runtime(NoCapabilities) == %Runtime{}
    end

    test "the Spark :graphlaw section holds only Admission structs (no capability entity leaked in)" do
      entities = Spark.Dsl.Extension.get_entities(NoCapabilities, [:graphlaw])
      assert Enum.all?(entities, &(is_struct(&1, Admission) or is_struct(&1, Runtime)))
    end
  end

  describe "the step enum" do
    test "a step outside the 8 atoms is refused by the DSL schema" do
      assert_raise Spark.Error.DslError, fn ->
        Code.compile_string("""
        defmodule AshGraphLaw.Compat.DslFixtures.BadStep#{System.unique_integer([:positive])} do
          use Ash.Resource,
            domain: AshGraphLaw.Compat.DslFixtures.Domain,
            validate_domain_inclusion?: false,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshGraphLaw.Resource]

          attributes do
            uuid_primary_key :id
          end

          graphlaw do
            admission(:bad, step: :sparql_select, ceiling: :observe)
          end
        end
        """)
      end
    end
  end
end
