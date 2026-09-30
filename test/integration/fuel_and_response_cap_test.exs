# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.FuelAndResponseCapTest do
  @moduledoc """
  Fuel exhaustion and the response cap against the real pinned engine.

    * fuel is a per-transaction budget: the smallest budget that serves a request serves an
      unbounded sequence of them, and any smaller budget is a typed `:blocked_resource` refusal;
    * `:max_response_bytes` refuses an oversized engine response `:resource_limit` before it is
      copied out, frees the engine buffer (memory does not grow across repeats) and leaves the
      host serving.

  The wasm-free part covers the fuel derivation.
  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{Host, Refusal, WasmConfig}

  @nt "<urn:a:x> <urn:a:p> <urn:a:y> .\n"

  defp law_req do
    %{"op" => "law", "data" => %{"text" => @nt, "dialect" => "ntriples"}, "steps" => [%{"step" => "rdfs"}]}
  end

  describe "fuel derivation (no engine needed)" do
    test "fuel follows the deadline unless set explicitly" do
      assert WasmConfig.limits(timeout_ms: 1_000, fuel_per_ms: 1_000).fuel == 1_000_000
      assert WasmConfig.limits(fuel: 42).fuel == 42
      assert WasmConfig.limits(fuel: 0).fuel == WasmConfig.limits([]).fuel
    end
  end

  describe "fuel (real engine)" do
    @describetag :wasm

    test "a starved host answers a typed :blocked_resource refusal on every call and is never dead" do
      # positive control: default fuel serves the same request
      assert {:ok, %{"ok" => true}} = Host.request(start_host!([]), law_req())

      starved = start_host!(fuel: 1)

      for _ <- 1..3 do
        assert {:error, %Refusal{code: code, class: :blocked_resource}} = Host.request(starved, law_req())
        assert code in [:fuel_exhausted, :call_trapped]
      end

      assert Process.alive?(starved)
    end

    test "fuel is per transaction: the least budget that serves one request serves many" do
      budgets = [10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000]

      {budget, host} =
        Enum.find_value(budgets, fn fuel ->
          host = start_host!(fuel: fuel)

          case Host.request(host, law_req()) do
            {:ok, %{"ok" => true}} -> {fuel, host}
            {:error, %Refusal{class: :blocked_resource}} -> nil
          end
        end) || flunk("no budget up to 1e9 served a one-triple law request")

      IO.puts("[fuel_test] least serving budget observed: #{budget}")

      # a cumulative budget would starve somewhere in this sequence
      for _ <- 1..25, do: assert({:ok, %{"ok" => true}} = Host.request(host, law_req()))

      # and every budget below the serving one refuses typed
      case Enum.filter(budgets, &(&1 < budget)) do
        [] ->
          :ok

        lower ->
          for fuel <- lower do
            assert {:error, %Refusal{class: :blocked_resource}} = Host.request(start_host!(fuel: fuel), law_req())
          end
      end
    end

    test "a request that ran out of fuel does not poison the next host built from the same module" do
      starved = start_host!(fuel: 1)
      assert {:error, %Refusal{class: :blocked_resource}} = Host.request(starved, law_req())

      healthy = start_host!([])
      assert {:ok, %{"ok" => true}} = Host.request(healthy, law_req())
    end
  end

  describe "response cap (real engine)" do
    @describetag :wasm

    test "an oversized response is refused :resource_limit, the buffer is freed and the host keeps serving" do
      # positive control: the default cap passes the same response
      normal = start_host!([])
      assert {:ok, %{"ok" => true} = full} = Host.request(normal, %{"op" => "capabilities"})
      full_size = full |> Jason.encode!() |> byte_size()
      assert full_size > 100

      capped = start_host!(max_response_bytes: 100)
      assert {:error, %Refusal{code: :resource_limit, class: :blocked_resource, details: details}} =
               Host.request(capped, %{"op" => "capabilities"})

      assert details.max_response_bytes == 100
      assert details.bytes > 100

      # warm: allocator state settles after the first refused response
      assert {:ok, warm} = Host.memory_size(capped)

      for _ <- 1..25 do
        assert {:error, %Refusal{code: :resource_limit}} = Host.request(capped, %{"op" => "capabilities"})
      end

      # the engine buffer was freed each time: linear memory did not grow
      assert {:ok, ^warm} = Host.memory_size(capped)
      assert Host.available?(capped, 5_000)
    end

    test "a response exactly at the cap is served, one byte under it is refused" do
      probe = start_host!([])
      assert {:ok, %{"ok" => true}} = Host.request(probe, %{"op" => "capabilities"})

      # find the response length the engine reports, through the refusal detail of a tiny cap
      tiny = start_host!(max_response_bytes: 1)
      assert {:error, %Refusal{code: :resource_limit, details: %{bytes: bytes}}} = Host.request(tiny, %{"op" => "capabilities"})

      at_cap = start_host!(max_response_bytes: bytes)
      assert {:ok, %{"ok" => true}} = Host.request(at_cap, %{"op" => "capabilities"})

      under = start_host!(max_response_bytes: bytes - 1)
      assert {:error, %Refusal{code: :resource_limit}} = Host.request(under, %{"op" => "capabilities"})
    end
  end
end
