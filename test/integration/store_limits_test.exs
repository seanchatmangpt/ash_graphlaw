# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.StoreLimitsTest do
  @moduledoc """
  Wasmtime store limits (`memories`, `instances`, `tables`, `table_elements`,
  `memory_limit_bytes`) against the real pinned engine (assurance claim 5 gaps).

  `memory_limit_bytes`, `instances` and `memories` are binding for any engine that exports a
  memory and needs one instance, so a host started with `0`/tiny values MUST be refused with a
  typed refusal. `tables` and `table_elements` bind only if the engine declares a table that
  large; for those two the test asserts "typed refusal OR served", prints which one it observed,
  and never claims the limit bound when it did not.

  The wasm-free part proves the limit keys reach `WasmConfig.limits/1`.
  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{Host, Refusal, WasmConfig}

  @typed_codes [
    :instantiation_failed,
    :call_trapped,
    :abi_failure,
    :call_exited,
    :fuel_exhausted,
    :resource_limit,
    :call_timeout
  ]
  @classes [:refused_authority, :refused_identity, :refused_structure, :blocked_resource]

  describe "limit plumbing (no engine needed)" do
    test "each store limit key is read from opts and wins over the default" do
      limits =
        WasmConfig.limits(
          memory_limit_bytes: 1_048_576,
          instances: 3,
          tables: 2,
          memories: 1,
          table_elements: 512
        )

      assert limits.memory_limit_bytes == 1_048_576
      assert limits.instances == 3
      assert limits.tables == 2
      assert limits.memories == 1
      assert limits.table_elements == 512
    end

    test "non-positive and non-integer limits are ignored, never applied as zero" do
      defaults = WasmConfig.limits([])

      for bad <- [0, -1, "4", nil, 1.5] do
        limits = WasmConfig.limits(memories: bad, instances: bad, tables: bad, table_elements: bad, memory_limit_bytes: bad)
        assert limits.memories == defaults.memories
        assert limits.instances == defaults.instances
        assert limits.tables == defaults.tables
        assert limits.table_elements == defaults.table_elements
        assert limits.memory_limit_bytes == defaults.memory_limit_bytes
      end
    end
  end

  describe "with the real engine" do
    @describetag :wasm

    # A host that cannot instantiate retries in the background; keep the retry quiet.
    defp limited_host(limits), do: start_host!(Keyword.merge([retry_base_ms: 600_000, retry_max_ms: 600_000], limits))

    defp assert_typed_refusal(host) do
      assert {:error, %Refusal{code: code, class: class}} = Host.request(host, %{"op" => "capabilities"})
      assert code in @typed_codes, "untyped code #{inspect(code)}"
      assert class in @classes
      assert Process.alive?(host)
      code
    end

    test "positive control: default limits serve and report a memory under the limit" do
      host = start_host!([])
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities"})
      assert {:ok, size} = Host.memory_size(host)
      assert size > 0 and size <= WasmConfig.limits([]).memory_limit_bytes
    end

    test "memory_limit_bytes below the engine's initial memory refuses the host, typed" do
      code = assert_typed_refusal(limited_host(memory_limit_bytes: 65_536))
      IO.puts("[store_limits] memory_limit_bytes=65536 observed: #{inspect(code)}")
    end

    test "memories: 0 refuses the host (the engine exports a memory)" do
      code = assert_typed_refusal(limited_host(memories: 0))
      IO.puts("[store_limits] memories=0 observed: #{inspect(code)}")
    end

    test "instances: 0 refuses the host (the engine needs one instance)" do
      code = assert_typed_refusal(limited_host(instances: 0))
      IO.puts("[store_limits] instances=0 observed: #{inspect(code)}")
    end

    test "tables: 0 and table_elements: 1 are refused typed or served, and the observation is printed" do
      for {label, opts} <- [tables_0: [tables: 0], table_elements_1: [table_elements: 1]] do
        host = limited_host(opts)

        observed =
          case Host.request(host, %{"op" => "capabilities"}) do
            {:ok, %{"ok" => true}} -> :served_limit_not_binding
            {:error, %Refusal{code: code, class: class}} when code in @typed_codes and class in @classes -> {:refused, code}
          end

        IO.puts("[store_limits] #{label} observed: #{inspect(observed)}")
        assert Process.alive?(host)
      end
    end

    test "engine memory never exceeds a small memory_limit_bytes under a large request, and the host survives" do
      limit = 64 * 1_048_576
      host = start_host!(memory_limit_bytes: limit, recycle_bytes: limit)
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities"})

      big = %{"op" => "sniff", "text" => String.duplicate("a", 24 * 1_048_576)}

      case Host.request(host, big, timeout: 30_000) do
        {:ok, %{}} -> :ok
        {:error, %Refusal{code: code, class: class}} -> assert code in @typed_codes and class in @classes
      end

      if Host.available?(host, 10_000) do
        assert {:ok, size} = Host.memory_size(host)
        assert size <= limit
      end

      assert Process.alive?(host)
    end
  end
end
