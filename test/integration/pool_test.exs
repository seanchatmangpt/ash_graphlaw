# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.PoolTest do
  @moduledoc """
  Real-wasm pool tests: members are real supervised hosts.
  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{Host, Pool, Refusal}

  @moduletag :wasm
  @moduletag :slow

  @nt "<urn:a:x> <urn:a:p> <urn:a:y> .\n"

  defp law_req do
    %{"op" => "law", "data" => %{"text" => @nt, "dialect" => "ntriples"}, "steps" => [%{"step" => "rdfs"}]}
  end

  defp members, do: Registry.lookup(Pool.registry(), :members)

  defp eventually(fun, attempts \\ 100) do
    case fun.() do
      {:ok, _} = ok ->
        ok

      other when attempts > 0 ->
        Process.sleep(100)

        eventually(fun, attempts - 1)
        |> case do
          {:ok, _} = ok -> ok
          _ -> other
        end

      other ->
        other
    end
  end

  test "a pool of size 3 registers 3 members and serves concurrent requests" do
    start_pool!(size: 3)
    assert {:ok, %{"ok" => true}} = Pool.request(%{"op" => "capabilities"})
    assert length(members()) == 3

    results =
      1..30
      |> Task.async_stream(fn _ -> Pool.request(law_req(), timeout: 30_000) end, max_concurrency: 30, timeout: 60_000)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.all?(results, &match?({:ok, %{"ok" => true}}, &1))
    assert results |> Enum.uniq() |> length() == 1
  end

  test "killing a member host is recovered and calls continue" do
    start_pool!(size: 3)
    # positive control
    assert {:ok, %{"ok" => true}} = Pool.request(%{"op" => "capabilities"})
    [{victim, _} | _] = members()
    ref = Process.monitor(victim)
    Process.exit(victim, :kill)
    assert_receive {:DOWN, ^ref, :process, ^victim, :killed}, 5_000

    assert {:ok, %{"ok" => true}} = eventually(fn -> Pool.request(%{"op" => "capabilities"}) end)
    assert {:ok, _} = eventually(fn -> if length(members()) == 3, do: {:ok, :full}, else: :short end)
    refute victim in Enum.map(members(), &elem(&1, 0))
    assert {:ok, %{"ok" => true}} = Pool.request(law_req())
  end

  test "saturation with max_queue 1 sheds load as :saturated and recovers" do
    start_pool!(size: 1, max_queue: 1)
    # positive control: an idle pool serves
    assert {:ok, %{"ok" => true}} = Pool.request(%{"op" => "capabilities"})

    rules = [
      %{"head" => ["?x", "https://e/anc", "?y"], "body" => [["?x", "https://e/par", "?y"]]},
      %{
        "head" => ["?x", "https://e/anc", "?z"],
        "body" => [["?x", "https://e/anc", "?y"], ["?y", "https://e/par", "?z"]]
      }
    ]

    facts = for i <- 1..120, do: ["https://e/n#{i}", "https://e/par", "https://e/n#{i + 1}"]
    heavy = %{"op" => "datalog", "rules" => rules, "facts" => facts}

    results =
      1..64
      |> Task.async_stream(fn _ -> Pool.request(heavy, timeout: 60_000) end, max_concurrency: 64, timeout: 120_000)
      |> Enum.map(fn {:ok, r} -> r end)

    saturated = Enum.filter(results, &match?({:error, %Refusal{code: :saturated, class: :blocked_resource}}, &1))
    served = Enum.filter(results, &match?({:ok, %{"ok" => true}}, &1))

    IO.puts("[pool_test] saturation: served=#{length(served)} saturated=#{length(saturated)}")
    assert saturated != []
    assert served != []
    assert length(saturated) + length(served) == 64

    # after the burst drains the pool serves again
    assert {:ok, %{"ok" => true}} = eventually(fn -> Pool.request(%{"op" => "capabilities"}) end)
    assert Host.available?(elem(hd(members()), 0), 5_000)
  end
end
