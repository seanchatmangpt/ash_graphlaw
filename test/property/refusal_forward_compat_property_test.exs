# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.RefusalForwardCompatTest do
  # UNSUPPORTED(generator-capability): hand-written forward-compatibility property suite.
  use AshGraphLaw.Test.PropertyCase, async: true

  defp hostile_map do
    map_of(word(), json_value(), max_length: 6)
  end

  describe "positive control" do
    test "a known payload with an injected unknown key keeps raw and its code" do
      payload = %{"kind" => "Ambiguous", "unknown_key" => [1]}
      refusal = Refusal.from_engine(payload)
      assert refusal.code == :engine_refused
      assert refusal.raw == payload
    end
  end

  describe "from_engine/2 forward compatibility" do
    property "injected unknown top-level keys never change the code and are kept in raw" do
      check all(base <- engine_error(), extra <- hostile_map(), max_runs: max_runs()) do
        if is_map(base) do
          extra = Map.drop(extra, ["kind", "details", "message", "engine", "dialect"])
          baseline = Refusal.from_engine(base)
          injected = Map.merge(base, extra)
          refusal = Refusal.from_engine(injected)
          assert refusal.code == baseline.code
          assert refusal.raw == injected
        end
      end
    end

    property "unknown codes, kinds and mistyped fields never raise and stay in the closed table" do
      check all(
              code <- one_of([word(), integer(), constant(nil), list_of(word(), max_length: 2)]),
              kind <- one_of([word(), integer(), constant(nil), hostile_map()]),
              details <- one_of([hostile_map(), integer(), word(), constant(nil)]),
              message <- one_of([word(), integer(), hostile_map()]),
              max_runs: max_runs()
            ) do
        payload = %{"kind" => kind, "message" => message, "details" => %{"code" => code, "nested" => details}}
        refusal = Refusal.from_engine(payload, %{})
        assert %Refusal{} = refusal
        assert refusal.code in Refusal.codes()
        assert refusal.class == Refusal.class_of(refusal.code)
        assert refusal.raw == payload
      end
    end

    property "arbitrary terms never raise, and raw is a map or nil" do
      check all(
              term <- engine_error(),
              details <- one_of([hostile_map(), integer(), constant(nil)]),
              max_runs: max_runs()
            ) do
        refusal = Refusal.from_engine(term, details)
        assert refusal.code in Refusal.codes()
        assert is_map(refusal.raw) or is_nil(refusal.raw)
      end
    end
  end

  describe "build/3" do
    property "accepts exactly the closed table" do
      check all(code <- refusal_code(), foreign <- foreign_code(), message <- word(), max_runs: max_runs()) do
        assert %Refusal{code: ^code, raw: nil} = Refusal.build(code, message)
        assert_raise ArgumentError, fn -> Refusal.build(foreign, message) end
      end
    end
  end
end
