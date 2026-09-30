# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.AdmissionsTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite; real Spark resource, real Contract.
  use AshGraphLaw.Test.PropertyCase, async: true

  alias AshGraphLaw.{Admissions, Contract}
  alias AshGraphLaw.Test.Ticket

  @declared [:ticket_shape, :ticket_close]

  describe "positive controls" do
    test "Ticket declares its admissions in order and fetch resolves each" do
      assert Enum.map(Admissions.all(Ticket), & &1.name) == @declared

      for name <- @declared do
        assert {:ok, %{name: ^name}} = Admissions.fetch(Ticket, name)
      end
    end

    test "a duplicate name is refused by the contract" do
      dup = [%AshGraphLaw.Dsl.Admission{name: :a, step: :rdfs}, %AshGraphLaw.Dsl.Admission{name: :a, step: :rdfs}]
      assert {:error, [%{code: :duplicate_admission}]} = Contract.validate(%{graphlaw: dup})
    end
  end

  describe "Admissions.all/1 and fetch/2" do
    property "all/1 is idempotent and ordered as declared" do
      check all(_n <- integer(1..5), max_runs: max_runs()) do
        first = Admissions.all(Ticket)
        assert first == Admissions.all(Ticket)
        assert Enum.map(first, & &1.name) == @declared
      end
    end

    property "fetch/2 of a declared name agrees with all/1; any other atom is :unknown_admission naming the known set" do
      check all(
              name <- one_of([member_of(@declared), map(word(), &String.to_atom("undeclared_" <> &1))]),
              max_runs: max_runs()
            ) do
        result = Admissions.fetch(Ticket, name)

        if name in @declared do
          assert {:ok, admission} = result
          assert admission in Admissions.all(Ticket)
        else
          assert {:error, %Refusal{code: :unknown_admission, details: %{known: known}}} = result
          assert known == @declared
        end
      end
    end

    property "modules without the extension have no admissions and refuse every name" do
      check all(
              mod <- member_of([Enum, String, Kernel, NoSuchModuleForProperty]),
              name <- admission_name(),
              max_runs: max_runs()
            ) do
        assert Admissions.all(mod) == []
        assert {:error, %Refusal{code: :unknown_admission}} = Admissions.fetch(mod, name)
      end
    end
  end

  describe "Contract over generated admission lists" do
    defp duplicate_names(list) do
      list
      |> Enum.frequencies_by(& &1.name)
      |> Enum.filter(fn {_n, c} -> c > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()
    end

    property "duplicates are refused exactly once per duplicated name; unique lists are :ok" do
      check all(list <- admission_list(), max_runs: max_runs()) do
        result = Contract.validate(%{graphlaw: list})

        case duplicate_names(list) do
          [] ->
            assert result == :ok

          names ->
            assert {:error, refusals} = result
            assert Enum.all?(refusals, &(&1.code == :duplicate_admission))
            assert length(refusals) == length(names)

            for name <- names, do: assert(Enum.any?(refusals, &(&1.detail =~ inspect(name))))
        end
      end
    end

    property "the verdict is insensitive to admission order and idempotent" do
      check all(list <- admission_list(), seed <- integer(), max_runs: max_runs()) do
        shuffled = Enum.sort_by(list, &:erlang.phash2({&1.name, &1.ceiling, seed}))

        assert Contract.validate(%{graphlaw: list}) == Contract.validate(%{graphlaw: shuffled})
        assert Contract.validate(%{graphlaw: list}) == Contract.validate(%{graphlaw: list})
      end
    end
  end
end
