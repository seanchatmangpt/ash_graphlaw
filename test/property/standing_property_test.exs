# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.StandingTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite; real Standing and Evidence.
  use AshGraphLaw.Test.PropertyCase, async: true

  alias AshGraphLaw.{Admitted, Evidence, Standing}

  describe "positive controls" do
    test "an admission is PARTIAL_ALIVE and each refusal class maps as documented" do
      assert Standing.of({:ok, Admitted.from_map(%{})}) == :PARTIAL_ALIVE
      assert Standing.of({:error, Refusal.new(:saturated)}) == :BLOCKED
      assert Standing.of({:error, Refusal.new(:unsupported_step)}) == :UNSUPPORTED
      assert Standing.of({:error, Refusal.new(:not_admitted)}) == :UNKNOWN
    end
  end

  describe "Standing.of/1" do
    property "is total over generated results and lands in the closed vocabulary" do
      check all(input <- standing_input(), max_runs: max_runs()) do
        assert Standing.of(input) in Standing.all()
        assert Standing.valid?(Standing.of(input))
      end
    end

    property "never returns :ALIVE: admission alone is not exact-SHA execution" do
      check all(input <- standing_input(), max_runs: max_runs()) do
        refute Standing.of(input) == :ALIVE
        refute Standing.of(input) == :BUILD_BROKEN
      end
    end

    property "an admitted result is PARTIAL_ALIVE regardless of receipts and states" do
      check all(admitted <- admitted(), max_runs: max_runs()) do
        assert Standing.of({:ok, admitted}) == :PARTIAL_ALIVE
      end
    end

    property "refusal standing follows the class" do
      check all(refusal <- refusal(), max_runs: max_runs()) do
        expected =
          case refusal.class do
            :blocked_resource -> :BLOCKED
            :unsupported -> :UNSUPPORTED
            _ -> :UNKNOWN
          end

        assert Standing.of({:error, refusal}) == expected
      end
    end

    property "non-result terms are :UNKNOWN" do
      check all(term <- json_value(), max_runs: max_runs()) do
        assert Standing.of(term) == :UNKNOWN
      end
    end
  end

  describe "Evidence over generated admissions" do
    property "standing is never ALIVE and the digest binds the exact input digest" do
      check all(
              admitted <- admitted(),
              input <- sha256_hex(),
              other <- sha256_hex(),
              name <- word(),
              max_runs: max_runs()
            ) do
        evidence = Evidence.new(name, admitted, input)
        assert evidence.standing == :PARTIAL_ALIVE
        assert evidence.digest =~ ~r/\A[0-9a-f]{64}\z/
        assert evidence.digest == Evidence.digest(evidence)
        assert evidence == Evidence.new(name, admitted, input)

        if other != input do
          refute Evidence.new(name, admitted, other).digest == evidence.digest
        end
      end
    end

    property "canonical JSON is insensitive to map key order" do
      check all(map <- json_map(), max_runs: max_runs()) do
        reversed = map |> Enum.reverse() |> Map.new()
        assert Evidence.canonical_json(map) == Evidence.canonical_json(reversed)
        assert Evidence.canonical_json(map) == Evidence.canonical_json(map)
      end
    end

    property "an evidence with no input digest still never claims ALIVE" do
      check all(admitted <- admitted(), max_runs: max_runs()) do
        evidence = Evidence.new("x", admitted, nil)
        assert evidence.input_digest == nil
        assert evidence.standing == :PARTIAL_ALIVE
      end
    end
  end
end
