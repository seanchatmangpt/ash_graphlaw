# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.CapabilityHelpersTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite for the capability helpers.
  use AshGraphLaw.Test.PropertyCase, async: true

  alias AshGraphLaw.Capability.CanonicalJSON
  alias AshGraphLaw.Capability.Coerce
  alias AshGraphLaw.Capability.Decode

  defp int_json_value do
    scalar = one_of([constant(nil), boolean(), integer(-1_000_000..1_000_000), text()])

    tree(scalar, fn child ->
      one_of([list_of(child, max_length: 4), map_of(word(), child, max_length: 4)])
    end)
  end

  defp any_json_value, do: json_value()

  describe "positive controls" do
    test "a fixed document round-trips and stringify is stable" do
      doc = %{"b" => [1, %{"a" => nil}], "a" => "é"}
      assert doc |> CanonicalJSON.encode() |> Jason.decode!() == doc
      assert Coerce.stringify(doc) == doc
      assert Decode.value(doc, "object") == doc
    end
  end

  describe "properties" do
    property "canonical encode then Jason.decode is the identity on float-free JSON" do
      check all(value <- int_json_value(), max_runs: max_runs()) do
        assert value |> CanonicalJSON.encode() |> Jason.decode!() == value
      end
    end

    property "canonical encoding is deterministic and its digest is a sha256 literal" do
      check all(value <- int_json_value(), max_runs: max_runs()) do
        assert CanonicalJSON.encode(value) == CanonicalJSON.encode(value)
        assert "sha256:" <> hex = CanonicalJSON.sha256(value)
        assert hex =~ ~r/\A[0-9a-f]{64}\z/
      end
    end

    property "canonical encoding is invariant under map insertion order" do
      check all(map <- map_of(word(), int_json_value(), max_length: 6), max_runs: max_runs()) do
        reversed = map |> Map.to_list() |> Enum.reverse() |> Map.new()
        assert CanonicalJSON.encode(map) == CanonicalJSON.encode(reversed)
      end
    end

    property "digest ignores any stored registry_sha256" do
      check all(
              map <- map_of(word(), int_json_value(), max_length: 4),
              stored <- text(),
              max_runs: max_runs()
            ) do
        clean = Map.delete(map, "registry_sha256")

        assert CanonicalJSON.digest(clean) ==
                 CanonicalJSON.digest(Map.put(clean, "registry_sha256", stored))
      end
    end

    property "stringify is idempotent and keeps JSON values intact" do
      check all(value <- any_json_value(), max_runs: max_runs()) do
        once = Coerce.stringify(value)
        assert Coerce.stringify(once) == once
        assert once == value
      end
    end

    property "Decode.value never raises on arbitrary JSON, for any vocabulary type" do
      types =
        ~w(string integer boolean object any data_spec term json_or_string list<string> list<object>
           list<any> list<term> list<list<string>> list<list<term>> bogus)

      check all(value <- any_json_value(), type <- member_of(types), max_runs: max_runs()) do
        result = Decode.value(value, type)

        if type in ~w(term list<term> list<list<term>>) do
          assert result != :never_returned
        else
          assert result == value
        end
      end
    end

    property "Decode.get and Decode.variant never raise on arbitrary maps" do
      check all(map <- json_map(), name <- word(), max_runs: max_runs()) do
        _ = Decode.get(map, name, "term")

        assert Decode.variant(map, name, ["a", "b"]) in [:a, :b] or
                 match?({:unknown, _}, Decode.variant(map, name, ["a", "b"]))
      end
    end

    property "Coerce.request never raises on arbitrary args" do
      fields = [
        %{name: "data", type: "data_spec", required: true, order: 1, nullable: false, doc: "", enum: nil, default: nil},
        %{name: "note", type: "any", required: false, order: 2, nullable: false, doc: "", enum: nil, default: nil}
      ]

      check all(args <- one_of([json_map(), json_value()]), max_runs: max_runs()) do
        assert match?({:ok, _}, Coerce.request("op", fields, args)) or
                 match?({:error, _}, Coerce.request("op", fields, args))
      end
    end
  end
end
