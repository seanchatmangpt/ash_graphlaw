# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.StandingTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admitted
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Standing

  @names [:UNKNOWN, :PARTIAL_ALIVE, :ALIVE, :BLOCKED, :BUILD_BROKEN, :UNSUPPORTED]

  defp admitted do
    Admitted.from_map(%{
      "states" => ["s0", "s1"],
      "receipts" => [%{"step" => "shacl", "parent" => "s0", "child" => "s1", "authority" => "purrdf::shapes"}],
      "nquads" => "<urn:a:x> <urn:a:p> <urn:a:y> <urn:g> .\n"
    })
  end

  describe "vocabulary" do
    test "all/0 is exactly the six doctrine standings" do
      assert Enum.sort(Standing.all()) == Enum.sort(@names)
    end

    test "valid?/1 accepts every standing and rejects everything else" do
      for name <- @names, do: assert(Standing.valid?(name), inspect(name))

      for other <- [:alive, :REFUSED, "ALIVE", nil, 1, %{}] do
        refute Standing.valid?(other), inspect(other)
      end
    end
  end

  describe "describe/1" do
    test "every standing has a non-empty ontology definition; ALIVE says this library never assigns it" do
      for name <- @names do
        assert Standing.describe(name) =~ ~r/\S/, inspect(name)
      end

      assert Standing.describe(:ALIVE) =~ "never assigns it from admission alone"
    end

    test "a value outside the vocabulary has no definition" do
      # built at run time: the compiler would otherwise flag the deliberately out-of-vocabulary literal
      outside = String.to_atom("REFUSED")
      assert_raise FunctionClauseError, fn -> Standing.describe(outside) end
    end
  end

  describe "of/1" do
    test "positive control: an admitted result is PARTIAL_ALIVE (observed on exact input, consequence not executed)" do
      assert Standing.of({:ok, admitted()}) == :PARTIAL_ALIVE
    end

    test "an admitted result is never ALIVE" do
      refute Standing.of({:ok, admitted()}) == :ALIVE
    end

    test "a blocked_resource refusal is BLOCKED" do
      assert Standing.of({:error, Refusal.new(:saturated, "full")}) == :BLOCKED
    end

    test "an unsupported refusal is UNSUPPORTED" do
      assert Standing.of({:error, Refusal.new(:unsupported_step, "no")}) == :UNSUPPORTED
    end

    test "an admission refusal is UNKNOWN (typed REFUSED is carried by the Refusal, not by standing)" do
      assert Standing.of({:error, Refusal.new(:not_admitted, "no")}) == :UNKNOWN
    end

    test "non-result inputs are UNKNOWN" do
      for junk <- [:anything, nil, "ok", {:ok, :not_admitted_struct}, {:error, :not_a_refusal}, 42] do
        assert Standing.of(junk) == :UNKNOWN, inspect(junk)
      end
    end

    test "for every one of the 35 codes, standing follows the class rule and is never ALIVE" do
      for code <- Refusal.codes() do
        refusal = Refusal.new(code, "m")

        expected =
          case refusal.class do
            :blocked_resource -> :BLOCKED
            :unsupported -> :UNSUPPORTED
            _ -> :UNKNOWN
          end

        assert Standing.of({:error, refusal}) == expected, inspect(code)
        assert Standing.valid?(expected)
      end
    end
  end
end
