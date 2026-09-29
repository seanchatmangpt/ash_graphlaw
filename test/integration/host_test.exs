# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.HostTest do
  @moduledoc """
  Real-wasm host tests: no doubles, every value below was read from a response
  of the pinned `graphlaw.wasm` (shapes from graphlaw `tests/wasm_abi.rs`).
  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{Host, Refusal}

  @moduletag :wasm

  @nt "<urn:a:x> <urn:a:p> <urn:a:y> .\n"

  defp capabilities(host), do: Host.request(host, %{"op" => "capabilities"})

  defp law_req do
    %{
      "op" => "law",
      "data" => %{"text" => @nt, "dialect" => "ntriples"},
      "steps" => [%{"step" => "rdfs"}]
    }
  end

  test "capabilities reports ABI 1 and the pinned dialect surface" do
    host = start_host!([])
    assert {:ok, %{"ok" => true} = resp} = capabilities(host)
    assert resp["abi"] == 1
    caps = Enum.map(resp["authorities"], & &1["capability"])
    for c <- ["SPARQL 1.1/1.2", "SHACL", "ShEx 2.1", "Datalog", "Notation3"], do: assert(c in caps)
    assert Enum.any?(caps, &String.starts_with?(&1, "Knowledge hooks"))
    assert Host.available?(host, 5_000)
  end

  test "ops datalog, n3, hooks, law and policy are each served (not refused as unknown op)" do
    host = start_host!([])
    # positive control: a known op is ok
    assert {:ok, %{"ok" => true}} = capabilities(host)

    probes = [
      {"datalog", %{"op" => "datalog", "rules" => [], "facts" => []}},
      {"n3", %{"op" => "n3", "text" => "@prefix : <https://e/> . :s a :T ."}},
      {"hooks",
       %{
         "op" => "hooks",
         "pack" => %{"text" => "", "dialect" => "turtle"},
         "data" => %{"text" => "", "dialect" => "turtle"}
       }},
      {"law", law_req()},
      {"policy", %{"op" => "policy", "problem" => %{}, "policy" => %{}}}
    ]

    for {op, req} <- probes do
      assert {:ok, resp} = Host.request(host, req)
      # an unknown op is refused with a message naming it; a served op may succeed or refuse on content
      refute inspect(resp) =~ "unknown op", "op #{op} not served: #{inspect(resp)}"
    end

    # negative control: an op that does not exist IS refused
    assert {:ok, %{"ok" => false}} = Host.request(host, %{"op" => "nope"})
  end

  test "two sequential requests through one host succeed" do
    host = start_host!([])
    assert {:ok, %{"ok" => true}} = capabilities(host)
    assert {:ok, %{"ok" => true}} = capabilities(host)
  end

  test "50 concurrent requests through one host all succeed (transaction serialization)" do
    host = start_host!([])
    assert {:ok, %{"ok" => true}} = capabilities(host)

    results =
      1..50
      |> Task.async_stream(fn _ -> Host.request(host, law_req(), timeout: 30_000) end,
        max_concurrency: 50,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert length(results) == 50

    assert Enum.all?(results, &match?({:ok, %{"ok" => true}}, &1)),
           inspect(Enum.reject(results, &match?({:ok, %{"ok" => true}}, &1)))

    # serialization means identical requests produce identical responses
    bodies = results |> Enum.map(fn {:ok, r} -> r end) |> Enum.uniq()
    assert length(bodies) == 1
  end

  test "an over-limit request is refused typed and the host keeps serving (recycle path)" do
    host = start_host!([])
    assert {:ok, %{"ok" => true}} = capabilities(host)

    handler = "ash-graphlaw-recycle-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:ash_graphlaw, :host, :recycle],
      fn _e, m, meta, _ -> send(parent, {:recycled, m, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    # 16 MiB + 1 byte body: past the ABI request cap in every layer
    over = %{"op" => "capabilities", "pad" => String.duplicate("x", 16 * 1024 * 1024 + 1)}

    observed =
      case Host.request(host, over, timeout: 60_000) do
        {:error, %Refusal{code: code}} -> {:refusal, code}
        {:ok, %{"ok" => false, "error" => %{"details" => %{"code" => code}}}} -> {:engine, code}
      end

    IO.puts("[host_test] over-limit observed: #{inspect(observed)}")
    assert observed in [{:refusal, :resource_limit}, {:engine, "ResourceLimit"}, {:refusal, :abi_failure}]

    receive do
      {:recycled, _m, meta} -> IO.puts("[host_test] recycle observed: #{inspect(meta)}")
    after
      200 -> IO.puts("[host_test] no recycle needed for over-limit request")
    end

    # positive: host still serves afterwards
    assert {:ok, %{"ok" => true}} = capabilities(host)
  end

  test "fuel exhaustion is a typed blocked_resource refusal, not a crash" do
    # positive control: same request under default fuel succeeds
    normal = start_host!([])
    assert {:ok, %{"ok" => true}} = Host.request(normal, law_req())

    starved = start_host!(fuel: 1_000)
    result = Host.request(starved, law_req())

    observed =
      case result do
        {:error, %Refusal{code: code, class: class}} -> {code, class}
        {:ok, %{"ok" => true}} -> :completed
        {:ok, other} -> {:engine_response, other}
      end

    IO.puts("[host_test] fuel exhaustion observed: #{inspect(observed)}")
    assert {code, class} = observed
    assert code in [:fuel_exhausted, :call_trapped]
    assert class == :blocked_resource
    # the starved host stays alive (it may be recycled or unavailable, never dead)
    assert Process.alive?(starved)
  end

  test "non-UTF-8 input is refused :invalid_encoding without growing engine memory" do
    host = start_host!([])
    assert {:ok, %{"ok" => true}} = Host.request(host, law_req())
    assert {:ok, before} = Host.memory_size(host)
    assert before > 0

    bad = %{"op" => "parse", "text" => <<0xFF, 0xFE, 0xFD, 0x80>>, "dialect" => "turtle"}
    assert {:error, %Refusal{code: :invalid_encoding, class: :refused_structure}} = Host.request(host, bad)

    assert {:ok, after_size} = Host.memory_size(host)
    # bound: the engine committed at most 4 MiB (64 wasm pages) more for the refused request
    assert after_size - before <= 4 * 1024 * 1024
    assert {:ok, %{"ok" => true}} = capabilities(host)
  end
end
