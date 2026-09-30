# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.RefusalTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite over the closed code table.
  use AshGraphLaw.Test.PropertyCase, async: true

  @string_keys ~w(code class kind engine dialect message details broken_term raw)

  defp to_json_map(%Refusal{} = refusal) do
    refusal
    |> Map.from_struct()
    |> Map.delete(:__exception__)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), json_field(v)} end)
  end

  defp json_field(v) when is_atom(v) and not is_nil(v) and not is_boolean(v), do: Atom.to_string(v)
  defp json_field(v), do: v

  defp from_json_map(%{"code" => code, "message" => message, "details" => details}) do
    Refusal.new(String.to_existing_atom(code), message, details)
  end

  describe "positive controls" do
    test "every code of the table builds a consistent refusal" do
      for code <- Refusal.codes() do
        refusal = Refusal.new(code)
        assert refusal.code == code
        assert refusal.class == Refusal.class_of(code)
        assert refusal.broken_term == Refusal.broken_term_of(code)
        assert refusal.message == Refusal.doc_of(code)
      end
    end
  end

  describe "Refusal.new/3" do
    property "code, class and broken_term come from the closed table" do
      check all(refusal <- refusal(), max_runs: max_runs()) do
        assert refusal.code in Refusal.codes()
        assert refusal.class in Refusal.classes()
        assert refusal.broken_term in Refusal.broken_terms()
        assert refusal.class == Refusal.class_of(refusal.code)
        assert refusal.broken_term == Refusal.broken_term_of(refusal.code)
      end
    end

    property "message is the given text, or the code's documented meaning when nil or empty" do
      check all(code <- refusal_code(), message <- one_of([constant(nil), constant(""), text()]), max_runs: max_runs()) do
        refusal = Refusal.new(code, message)
        expected = if is_binary(message) and message != "", do: message, else: Refusal.doc_of(code)
        assert refusal.message == expected
        assert is_binary(refusal.message) and refusal.message != ""
        assert Exception.message(refusal) == refusal.message
      end
    end

    property "details survive untouched" do
      check all(code <- refusal_code(), details <- json_map(), max_runs: max_runs()) do
        assert Refusal.new(code, nil, details).details == details
      end
    end

    property "codes outside the table raise ArgumentError from every accessor" do
      check all(code <- foreign_code(), max_runs: max_runs()) do
        for fun <- [&Refusal.new/1, &Refusal.class_of/1, &Refusal.broken_term_of/1, &Refusal.doc_of/1] do
          assert_raise ArgumentError, fn -> fun.(code) end
        end
      end
    end
  end

  describe "serialization" do
    property "JSON round trip preserves code, class, broken_term, message and details" do
      check all(refusal <- refusal(), max_runs: max_runs()) do
        decoded = refusal |> to_json_map() |> Jason.encode!() |> Jason.decode!()
        assert Enum.sort(Map.keys(decoded)) == Enum.sort(@string_keys)

        rebuilt = from_json_map(decoded)
        assert rebuilt.code == refusal.code
        assert rebuilt.class == refusal.class
        assert rebuilt.broken_term == refusal.broken_term
        assert rebuilt.message == refusal.message
        assert rebuilt.details == decoded["details"]
      end
    end

    property "the class and broken_term of a code are stable across calls" do
      check all(code <- refusal_code(), max_runs: max_runs()) do
        assert Refusal.class_of(code) == Refusal.class_of(code)
        assert Refusal.new(code) == Refusal.new(code)
      end
    end
  end

  describe "Refusal.from_engine/2" do
    property "never raises and always yields a code of the closed table" do
      check all(error <- engine_error(), details <- json_map(), max_runs: max_runs()) do
        refusal = Refusal.from_engine(error, details)
        assert %Refusal{} = refusal
        assert refusal.code in Refusal.codes()
        assert refusal.class == Refusal.class_of(refusal.code)
        assert refusal.broken_term == Refusal.broken_term_of(refusal.code)
      end
    end

    property "a non-map payload is :engine_unclassified and keeps the raw inspection" do
      check all(
              term <- one_of([integer(), text(), constant(nil), list_of(integer(), max_length: 3)]),
              max_runs: max_runs()
            ) do
        refusal = Refusal.from_engine(term)
        assert refusal.code == :engine_unclassified
        assert refusal.details["raw"] == inspect(term)
      end
    end

    property "a known engine detail code selects its table code" do
      table = %{
        "NotAdmitted" => :not_admitted,
        "PlanRefused" => :plan_refused,
        "ReceiptRequired" => :receipt_required,
        "LeaseRefused" => :lease_refused,
        "ResourceLimit" => :resource_limit,
        "PolicyRefused" => :policy_refused,
        "ReceiptRefused" => :receipt_required,
        "UnverifiedLeaseRefused" => :lease_refused
      }

      check all(name <- member_of(Map.keys(table)), kind <- one_of([constant(nil), word()]), max_runs: max_runs()) do
        payload = %{"kind" => kind, "details" => %{"code" => name}}
        assert Refusal.from_engine(payload).code == Map.fetch!(table, name)
      end
    end
  end
end
