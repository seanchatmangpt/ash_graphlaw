# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.HostLifecycleTest do
  @moduledoc """
  Host and pool lifecycle against REAL WebAssembly modules run by the real Wasmtime.

  The engine here is `AshGraphLaw.Test.WasmFixtures.scripted_engine/1`, a spec-valid module that
  scripts the ABI edges a healthy GraphLaw cannot be asked to hit on demand: a trap, a slow
  `_initialize`, an oversized response, a table-growth attempt. It is loaded with
  `expected_sha256: :unpinned` (the caller chose the bytes and says so). It is never used to admit
  a graph; nothing about the pinned GraphLaw engine is claimed here.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks, no stubs.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Host
  alias AshGraphLaw.Pool
  alias AshGraphLaw.Test.WasmFixtures

  @capabilities %{"op" => "capabilities"}

  defp host!(opts) do
    start_host!(Keyword.merge([name: nil, expected_sha256: :unpinned], opts))
  end

  defp eventually(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never became true")
      true -> Process.sleep(50) && eventually(fun, tries - 1)
    end
  end

  defp registry!(name) do
    start_supervised!({Registry, keys: :duplicate, name: name})
    name
  end

  describe "the caller is answered before the recycle" do
    test "a trap returns its typed refusal immediately even when re-instantiation is slow" do
      # ~2 billion loop iterations in `_initialize`: about a second of Wasmtime time, per instance
      bytes = WasmFixtures.scripted_engine(call: :trap, init_iterations: 2_000_000_000)
      host = host!(bytes: bytes, instantiate_fuel: 100_000_000_000)

      # positive control: the host is live and its first (slow) instantiation succeeded
      assert Host.available?(host, 15_000)
      assert {:ok, %{recycles: 0}} = Host.info(host)

      {micros, result} = :timer.tc(fn -> Host.request(host, @capabilities, timeout: 5_000) end)

      assert {:error, %Refusal{code: :call_trapped}} = result
      assert micros < 500_000, "the caller waited #{div(micros, 1000)} ms: it was answered after the recycle"

      # the recycle still happens, after the reply: a call queues behind it and sees recycles: 1
      assert {:ok, %{recycles: 1}} = Host.info(host, 30_000)
      assert Host.available?(host, 30_000)
    end
  end

  describe "an unavailable host heals" do
    @tag :tmp_dir
    test "a load that failed is retried and the host becomes routable", %{tmp_dir: dir} do
      path = Path.join(dir, "engine.wasm")
      registry = registry!(:agl_heal_registry)

      host = host!(wasm_path: path, registry: registry, retry_base_ms: 20, retry_max_ms: 40)

      # not there yet: typed refusal, and the host is registered as unavailable, not as a member
      refute Host.available?(host)
      assert {:error, %Refusal{code: :wasm_not_vendored}} = Host.request(host, @capabilities)
      assert Pool.members(registry) == []
      assert Pool.unavailable_members(registry) == [host]

      # the engine appears; the next retry loads it
      File.write!(path, WasmFixtures.scripted_engine(call: {:respond, 0}))
      eventually(fn -> Host.available?(host) end)

      assert Pool.members(registry) == [host]
      assert Pool.unavailable_members(registry) == []

      # the healed host really runs the engine (the scripted engine answers with non-JSON)
      assert {:error, %Refusal{code: :invalid_json}} = Host.request(host, @capabilities)
    end

    @tag :tmp_dir
    test "a host whose engine keeps failing keeps retrying with capped backoff and never dies", %{tmp_dir: dir} do
      host = host!(wasm_path: Path.join(dir, "never.wasm"), retry_base_ms: 10, retry_max_ms: 20)

      for _ <- 1..5 do
        Process.sleep(30)
        assert Process.alive?(host)
        assert {:error, %Refusal{code: :wasm_not_vendored}} = Host.info(host)
      end
    end
  end

  describe "pool routing" do
    @tag :tmp_dir
    test "an unavailable member never wins the shortest-mailbox pick", %{tmp_dir: dir} do
      registry = registry!(:agl_pick_registry)
      live = host!(bytes: WasmFixtures.scripted_engine(call: {:respond, 0}), registry: registry)
      dead = host!(wasm_path: Path.join(dir, "gone.wasm"), registry: registry, retry_base_ms: 60_000)

      # positive control: the live member is routable and the dead one is registered as unavailable
      assert Pool.members(registry) == [live]
      assert Pool.unavailable_members(registry) == [dead]
      assert Pool.pick(registry) == live

      # both mailboxes are empty, which is exactly how the dead member used to win
      for _ <- 1..200, do: assert(Pool.pick(registry) == live)
    end

    test "equal mailboxes spread a burst across every live member instead of piling on the first" do
      registry = registry!(:agl_spread_registry)
      bytes = WasmFixtures.scripted_engine(call: {:respond, 0})
      hosts = for _ <- 1..4, do: host!(bytes: bytes, registry: registry)

      # positive control: all four are routable
      assert Enum.sort(Pool.members(registry)) == Enum.sort(hosts)

      picked = for _ <- 1..400, into: MapSet.new(), do: Pool.pick(registry)
      assert MapSet.equal?(picked, MapSet.new(hosts))
    end

    @tag :tmp_dir
    test "with no live member the caller gets the member's real refusal, not an opaque error", %{tmp_dir: dir} do
      start_pool!(size: 2, wasm_path: Path.join(dir, "absent.wasm"), expected_sha256: :unpinned, retry_base_ms: 60_000)

      assert Pool.pick() == nil
      assert length(Pool.unavailable_members()) == 2
      assert {:error, %Refusal{code: :wasm_not_vendored}} = Pool.request(@capabilities)
    end

    test "with no member at all the refusal is :host_not_started" do
      assert Pool.members() == []
      assert {:error, %Refusal{code: :host_not_started}} = Pool.request(@capabilities)
    end
  end

  describe "load shedding" do
    test "a host sheds with its OWN max_queue when overloaded, even though callers never pass one" do
      # every request spins ~50 ms inside the engine, then answers with non-JSON
      bytes = WasmFixtures.scripted_engine(call: {:spin, 100_000_000, 0})

      # positive control: an idle host serves (the engine ran and answered, it did not shed)
      idle = host!(bytes: bytes, max_queue: 1)
      assert {:error, %Refusal{code: :invalid_json}} = Host.request(idle, @capabilities, timeout: 10_000)

      results =
        1..30
        |> Task.async_stream(fn _ -> Host.request(idle, @capabilities, timeout: 10_000) end,
          max_concurrency: 30,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      shed = Enum.filter(results, &match?({:error, %Refusal{code: :saturated, class: :blocked_resource}}, &1))
      served = Enum.filter(results, &match?({:error, %Refusal{code: :invalid_json}}, &1))

      assert shed != [], "nothing was shed"
      assert served != [], "nothing was served"
      assert length(shed) + length(served) == 30

      # the burst drains and the host serves again
      assert {:error, %Refusal{code: :invalid_json}} = Host.request(idle, @capabilities, timeout: 10_000)
    end

    test "with the default bound the same size of burst is not shed" do
      bytes = WasmFixtures.scripted_engine(call: {:spin, 1_000_000, 0})
      host = host!(bytes: bytes)

      results =
        1..30
        |> Task.async_stream(fn _ -> Host.request(host, @capabilities, timeout: 10_000) end, max_concurrency: 30)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:error, %Refusal{code: :invalid_json}}, &1))
    end
  end

  describe "response cap" do
    test "a response larger than max_response_bytes is refused :resource_limit before it is read" do
      bytes = WasmFixtures.scripted_engine(call: {:respond, 2048})

      # positive control: under the default cap the 2048 bytes ARE read (and are not JSON)
      assert {:error, %Refusal{code: :invalid_json}} = Host.request(host!(bytes: bytes), @capabilities)

      capped = host!(bytes: bytes, max_response_bytes: 1_024)
      assert {:error, %Refusal{code: :resource_limit, details: details}} = Host.request(capped, @capabilities)
      assert details.bytes == 2_048
      assert details.max_response_bytes == 1_024

      # the host survives a refused response and still answers
      assert Host.available?(capped)
      assert {:error, %Refusal{code: :resource_limit}} = Host.request(capped, @capabilities)
    end
  end

  describe "store limits" do
    test "table growth is bounded by table_elements" do
      bytes = WasmFixtures.scripted_engine(call: :grow_table)

      # positive control: the default limit (100_000) allows 1000 more elements, so the scripted
      # engine reports the old size 1 as a 1-byte (non-JSON) response
      assert {:error, %Refusal{code: :invalid_json}} = Host.request(host!(bytes: bytes), @capabilities)

      # a tighter limit denies the growth; the engine reports -1, i.e. a 4 GiB response length
      tight = host!(bytes: bytes, table_elements: 10)

      assert {:error, %Refusal{code: :resource_limit, details: %{bytes: 4_294_967_295}}} =
               Host.request(tight, @capabilities)
    end
  end
end
