# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.WasmConfigTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite; real WasmConfig and Contract.
  use AshGraphLaw.Test.PropertyCase, async: false

  alias AshGraphLaw.{Contract, WasmConfig}
  alias AshGraphLaw.Dsl.Runtime

  @hex ~r/\A[0-9a-fA-F]{64}\z/
  @runtime_codes [:invalid_runtime_option, :invalid_trusted_key]

  defp config_free?(keys), do: Enum.all?(keys, &is_nil(Application.get_env(:ash_graphlaw, &1)))

  describe "positive controls" do
    test "default limits are positive integers and fuel follows the deadline" do
      limits = WasmConfig.limits([])
      assert Enum.all?(limits, fn {_k, v} -> is_integer(v) and v > 0 end)
      assert limits.fuel == limits.timeout_ms * limits.fuel_per_ms
    end

    test "a valid runtime section is :ok" do
      assert :ok =
               Contract.validate(%{
                 graphlaw: [%Runtime{timeout_ms: 10, max_skew_secs: 0, trusted_keys: [String.duplicate("a", 64)]}]
               })
    end
  end

  @store_count_keys [:table_elements, :instances, :tables, :memories]

  describe "WasmConfig.limits/1" do
    property "over random options every limit is a positive integer (store counts may be zero)" do
      check all(opts <- limit_opts(), max_runs: max_runs()) do
        limits = WasmConfig.limits(opts)
        assert Map.keys(limits) |> Enum.sort() == Enum.sort(limit_keys())

        assert Enum.all?(limits, fn {k, v} ->
                 is_integer(v) and if(k in @store_count_keys, do: v >= 0, else: v > 0)
               end)
      end
    end

    property "a valid positive-integer option wins; an invalid one falls back to a valid default" do
      check all(opts <- limit_opts(), max_runs: max_runs()) do
        limits = WasmConfig.limits(opts)

        if config_free?(limit_keys()) do
          for {key, value} <- opts, key != :fuel, is_integer(value) and value > 0 do
            assert Map.fetch!(limits, key) == value
          end

          fuel = Keyword.get(opts, :fuel)

          if is_integer(fuel) and fuel > 0 do
            assert limits.fuel == fuel
          else
            assert limits.fuel == limits.timeout_ms * limits.fuel_per_ms
          end
        end
      end
    end

    property "limits/1 is deterministic" do
      check all(opts <- limit_opts(), max_runs: max_runs()) do
        assert WasmConfig.limits(opts) == WasmConfig.limits(opts)
      end
    end
  end

  describe "WasmConfig path and pin options" do
    property "an explicit wasm_path wins path resolution" do
      check all(name <- word(), max_runs: max_runs()) do
        path = "/tmp/" <> name <> ".wasm"
        assert WasmConfig.wasm_path(wasm_path: path) == path
      end
    end

    property "an explicit foreign wasm_path is :unpinned; an explicit expected_sha256 always wins" do
      check all(name <- word(), sha <- one_of([sha256_hex(), constant(:unpinned)]), max_runs: max_runs()) do
        foreign = "/nonexistent-dir/" <> name <> ".wasm"
        assert WasmConfig.expected_sha256(wasm_path: foreign) == :unpinned
        assert WasmConfig.expected_sha256(wasm_path: foreign, expected_sha256: sha) == sha
        assert WasmConfig.expected_sha256(expected_sha256: sha) == sha
      end
    end
  end

  describe "Contract runtime option validation" do
    defp model_valid?(%Runtime{timeout_ms: t, max_skew_secs: s, trusted_keys: keys}) do
      is_integer(t) and t > 0 and is_integer(s) and s >= 0 and is_list(keys) and
        Enum.all?(keys, &(is_binary(&1) and Regex.match?(@hex, &1)))
    end

    property "random runtime sections are :ok exactly when they satisfy the documented shape" do
      check all(runtime <- runtime_struct(), max_runs: max_runs()) do
        result = Contract.validate(%{graphlaw: [runtime]})

        if model_valid?(runtime) do
          assert result == :ok
        else
          assert {:error, [_ | _] = refusals} = result

          for %{code: code, detail: detail} <- refusals do
            assert code in @runtime_codes
            assert code in Refusal.codes()
            assert is_binary(detail) and detail != ""
          end
        end
      end
    end

    property "refusal codes carry the failing field: timeout/skew -> option, keys -> trusted_key" do
      check all(runtime <- runtime_struct(), max_runs: max_runs()) do
        {:error, refusals} =
          case Contract.validate(%{graphlaw: [runtime]}) do
            :ok -> {:error, []}
            error -> error
          end

        option_details = for %{code: :invalid_runtime_option, detail: d} <- refusals, do: d
        key_details = for %{code: :invalid_trusted_key, detail: d} <- refusals, do: d

        assert Enum.all?(option_details, &(&1 =~ "timeout_ms" or &1 =~ "max_skew_secs"))
        assert Enum.all?(key_details, &(&1 =~ "trusted"))
      end
    end

    property "a malformed compiled state is refused, never :ok" do
      check all(
              term <- one_of([json_value(), constant(%{graphlaw: :nope}), constant(%{other: []})]),
              max_runs: max_runs()
            ) do
        assert {:error, [%{code: :invalid_runtime_option}]} = Contract.validate(term)
      end
    end
  end
end
