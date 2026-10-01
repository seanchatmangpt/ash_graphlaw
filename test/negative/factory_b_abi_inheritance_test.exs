# SPDX-License-Identifier: MIT
defmodule AshGraphLaw.FactoryBAbiInheritanceTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias AshGraphLaw.Mutation.Catalog

  test "R2 ABI identity is inherited by the mutation court" do
    assert {:ok, mutation} = Catalog.fetch("AGL-MUT-017")
    assert mutation.module == AshGraphLaw.Parity
    assert mutation.function == :same_abi
    assert mutation.arity == 2
    assert mutation.operator == {:replace_body, "true."}
    assert mutation.guard == "Parity runtime ABI identity (R2)"
    assert Enum.any?(mutation.killers, &String.starts_with?(&1, "test/negative/"))
  end

  test "R2 mutation remains append-only after the prior parity guards" do
    ids = Catalog.ids()
    assert Enum.find_index(ids, &(&1 == "AGL-MUT-015")) < Enum.find_index(ids, &(&1 == "AGL-MUT-016"))
    assert Enum.find_index(ids, &(&1 == "AGL-MUT-016")) < Enum.find_index(ids, &(&1 == "AGL-MUT-017"))
  end
end
