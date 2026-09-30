# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Negative.RefusalCapabilityCodesTest do
  # UNSUPPORTED(generator-capability): hand-written negative court for the capability codes 36..40.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Refusal

  @capability_codes [
    :invalid_capability_request,
    :unknown_capability,
    :capability_not_declared,
    :capability_parity_drift,
    :capability_response_undecodable
  ]

  describe "positive control" do
    test "every capability code builds through build/3 with a table class and term" do
      for code <- @capability_codes do
        refusal = Refusal.build(code, "m", %{"d" => 1})
        assert %Refusal{code: ^code, details: %{"d" => 1}, raw: nil} = refusal
        assert refusal.class in Refusal.classes()
        assert refusal.broken_term in Refusal.broken_terms()
      end
    end
  end

  describe "closed table" do
    test "the capability codes are the last five, in order 36..40" do
      assert Refusal.codes() |> Enum.take(-5) == @capability_codes
      assert length(Refusal.codes()) == 40
    end

    test "the 35 pre-existing codes are unchanged in front" do
      assert Refusal.codes() |> Enum.take(35) |> length() == 35
      assert hd(Refusal.codes()) == :not_admitted
      assert Enum.at(Refusal.codes(), 34) == :unsupported_step
    end

    test "per-code constructors exist for every capability code" do
      for code <- @capability_codes, do: assert(apply(Refusal, code, []).code == code)
    end

    test "build/3 raises ArgumentError for codes outside the table" do
      for bogus <- [:capability_missing, :NotAdmitted, nil, "unknown_capability", 40] do
        assert_raise ArgumentError, fn -> Refusal.build(bogus, "x") end
      end
    end

    test "capability codes are never produced by from_engine/2" do
      for payload <- [%{"details" => %{"code" => "unknown_capability"}}, %{"kind" => "unknown_capability"}] do
        refute Refusal.from_engine(payload).code in @capability_codes
      end
    end
  end
end
