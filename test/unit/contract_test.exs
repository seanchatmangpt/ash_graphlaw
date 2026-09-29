# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.ContractTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Contract
  alias AshGraphLaw.Dsl.Admission
  alias AshGraphLaw.Dsl.Runtime
  alias AshGraphLaw.Test.ShapeLaw

  @valid_key String.duplicate("ab", 32)
  @payload_steps [:shacl, :n3, :hooks, :plan, :require_receipt, :require_signed_receipt]

  # `compiled` is what Persist stores under :ash_graphlaw_compiled: %{graphlaw: entities}.
  defp compiled(entities), do: %{graphlaw: entities}

  defp admission(name, step, opts \\ []) do
    struct!(Admission, Keyword.merge([name: name, step: step, ceiling: :construct, law: nil, projection: nil], opts))
  end

  defp runtime(opts), do: struct!(Runtime, opts)

  defp codes({:error, refusals}), do: Enum.map(refusals, & &1.code)

  describe "positive controls" do
    test "an empty section is legal" do
      assert Contract.validate(compiled([])) == :ok
    end

    test "a fully valid runtime plus admissions is accepted" do
      entities = [
        runtime(timeout_ms: 1000, max_skew_secs: 0, trusted_keys: [@valid_key]),
        admission(:shape, :shacl, law: ShapeLaw),
        admission(:closure, :rdfs)
      ]

      assert Contract.validate(compiled(entities)) == :ok
    end

    test "admissions without a runtime entity are accepted (defaults apply)" do
      assert Contract.validate(compiled([admission(:closure, :owl_rl)])) == :ok
    end

    test "rdfs and owl_rl need no law module" do
      for step <- [:rdfs, :owl_rl] do
        assert Contract.validate(compiled([admission(:a, step)])) == :ok, inspect(step)
      end
    end

    test "every payload-bearing step is accepted once a law module is supplied" do
      for step <- @payload_steps do
        assert Contract.validate(compiled([admission(:a, step, law: ShapeLaw)])) == :ok, inspect(step)
      end
    end
  end

  describe "duplicate_admission" do
    test "two admissions with the same name are refused" do
      result =
        Contract.validate(compiled([admission(:same, :rdfs), admission(:same, :owl_rl)]))

      assert {:error, refusals} = result
      assert :duplicate_admission in codes(result)
      assert Enum.all?(refusals, &(is_atom(&1.code) and is_binary(&1.detail)))
    end

    test "distinct names are not a duplicate (control)" do
      assert Contract.validate(compiled([admission(:one, :rdfs), admission(:two, :rdfs)])) == :ok
    end
  end

  describe "missing_law_module" do
    for step <- @payload_steps do
      test "step #{step} without a law module is refused" do
        result = Contract.validate(compiled([admission(:needs_law, unquote(step))]))
        assert :missing_law_module in codes(result)
      end
    end
  end

  describe "invalid_trusted_key" do
    for {label, key} <- [
          {"too short", String.duplicate("a", 63)},
          {"too long", String.duplicate("a", 65)},
          {"non-hex characters", String.duplicate("z", 64)},
          {"empty", ""}
        ] do
      test "a #{label} trusted key is refused" do
        result = Contract.validate(compiled([runtime(trusted_keys: [unquote(key)])]))
        assert :invalid_trusted_key in codes(result)
      end
    end

    test "one bad key among good keys is still refused" do
      result = Contract.validate(compiled([runtime(trusted_keys: [@valid_key, "nope"])]))
      assert :invalid_trusted_key in codes(result)
    end

    test "several valid keys are accepted (control)" do
      keys = [@valid_key, String.duplicate("01", 32)]
      assert Contract.validate(compiled([runtime(trusted_keys: keys)])) == :ok
    end
  end

  describe "invalid_runtime_option" do
    test "timeout_ms of zero is refused" do
      assert :invalid_runtime_option in codes(Contract.validate(compiled([runtime(timeout_ms: 0)])))
    end

    test "a negative timeout_ms is refused" do
      assert :invalid_runtime_option in codes(Contract.validate(compiled([runtime(timeout_ms: -5)])))
    end

    test "a negative max_skew_secs is refused" do
      assert :invalid_runtime_option in codes(Contract.validate(compiled([runtime(max_skew_secs: -1)])))
    end

    test "max_skew_secs of zero and timeout_ms of one are the accepted boundaries (control)" do
      assert Contract.validate(compiled([runtime(timeout_ms: 1, max_skew_secs: 0)])) == :ok
    end
  end

  describe "aggregation" do
    test "distinct violations are all reported together, each with a detail string" do
      result =
        Contract.validate(
          compiled([
            runtime(timeout_ms: 0, trusted_keys: ["short"]),
            admission(:dup, :shacl),
            admission(:dup, :rdfs)
          ])
        )

      assert {:error, refusals} = result
      found = codes(result)

      assert :invalid_runtime_option in found
      assert :invalid_trusted_key in found
      assert :duplicate_admission in found
      assert :missing_law_module in found
      assert Enum.all?(refusals, &(is_binary(&1.detail) and &1.detail != ""))
    end
  end
end
