# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Ash.DslTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test; reads only the Admissions/Spark APIs.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Dsl.{Admission, Runtime}
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Test.Ticket

  defmodule Plain do
    @moduledoc false
    def hello, do: :world
  end

  defmodule Bare.Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshGraphLaw.Ash.DslTest.Bare
    end
  end

  defmodule Bare do
    @moduledoc false
    use Ash.Resource,
      domain: AshGraphLaw.Ash.DslTest.Bare.Domain,
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

  describe "Test.Ticket declarations" do
    test "positive control: the fixture compiles and is an Ash resource" do
      assert Ash.Resource.Info.resource?(Ticket)
      assert [_ | _] = Admissions.all(Ticket)
    end

    test "both admissions are returned with the declared fields" do
      admissions = Admissions.all(Ticket)
      assert Enum.all?(admissions, &match?(%Admission{}, &1))
      assert admissions |> Enum.map(& &1.name) |> Enum.sort() == [:ticket_close, :ticket_shape]

      {:ok, shape} = Admissions.fetch(Ticket, :ticket_shape)
      assert shape.step == :shacl
      assert shape.law == AshGraphLaw.Test.ShapeLaw
      assert shape.ceiling in [:observe, :select, :construct]

      {:ok, close} = Admissions.fetch(Ticket, :ticket_close)
      assert close.step == :plan
      assert close.ceiling == :select
      assert close.law == AshGraphLaw.Test.PlanLaw
    end

    test "runtime/1 returns the declared runtime section" do
      assert %Runtime{timeout_ms: 5000} = Admissions.runtime(Ticket)
    end

    test "the read side equals what Spark reports for the :graphlaw section" do
      entities = Spark.Dsl.Extension.get_entities(Ticket, [:graphlaw])
      assert Enum.filter(entities, &is_struct(&1, Admission)) == Admissions.all(Ticket)
      assert Enum.count(entities, &is_struct(&1, Runtime)) == 1
    end

    test "the extension is registered on the resource" do
      assert AshGraphLaw.Resource in Spark.extensions(Ticket)
    end
  end

  describe "resource without a runtime entity" do
    test "positive control: its admission is readable" do
      assert {:ok, %Admission{name: :observed, step: :rdfs, ceiling: :observe, law: nil}} =
               Admissions.fetch(Bare, :observed)
    end

    test "runtime/1 falls back to a Runtime struct" do
      assert %Runtime{} = runtime = Admissions.runtime(Bare)
      assert runtime.timeout_ms in [nil, 5000]
    end
  end

  describe "typed refusals from the read side" do
    test "unknown admission name on a real resource is :unknown_admission" do
      assert {:ok, %Admission{}} = Admissions.fetch(Ticket, :ticket_shape)

      assert {:error, %Refusal{code: :unknown_admission, class: :refused_structure, details: details}} =
               Admissions.fetch(Ticket, :no_such_admission)

      assert :ticket_shape in details.known
    end

    test "a module without the extension has no admissions and refuses fetch" do
      assert Admissions.all(Plain) == []
      assert {:error, %Refusal{code: :unknown_admission}} = Admissions.fetch(Plain, :anything)
      assert %Runtime{} = Admissions.runtime(Plain)
    end
  end
end
