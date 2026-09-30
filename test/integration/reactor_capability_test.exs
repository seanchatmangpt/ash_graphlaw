# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Reactor court.
defmodule AshGraphLaw.Integration.ReactorCapabilityTest do
  @moduledoc """
  Runs real Reactors with the GraphLaw steps against the real engine. The hook pack and data
  are graphlaw's `packs/self-monitoring-pack` (read-only; override the root with
  `GRAPHLAW_REPO`). Firing count 3 is asserted by graphlaw's own `tests/wasm_abi.rs`.
  """
  use AshGraphLaw.Test.Case, async: false

  @moduletag :wasm

  alias AshGraphLaw.Refusal

  defmodule HooksReactor do
    @moduledoc false
    use Reactor

    input(:pack)
    input(:data)
    input(:server)

    step :fire, AshGraphLaw.Reactor.Hooks do
      argument :pack, input(:pack)
      argument :data, input(:data)
      options(server: input(:server))
    end

    return :fire
  end

  defmodule SniffReactor do
    @moduledoc false
    use Reactor

    input(:text)
    input(:server)

    step :sniff, AshGraphLaw.Reactor.Capability do
      argument :text, input(:text)
      options(op: "sniff")
    end

    return :sniff
  end

  defp repo_root, do: System.get_env("GRAPHLAW_REPO") || Path.expand("~/graphlaw")

  defp fixture!(rel) do
    path = Path.join(repo_root(), rel)

    case File.read(path) do
      {:ok, text} -> %{"text" => text, "dialect" => "turtle"}
      {:error, reason} -> flunk("hook fixture #{path} unreadable: #{inspect(reason)}")
    end
  end

  test "positive control: the Reactor steps are real, not stubs" do
    assert AshGraphLaw.Reactor.available?()
    assert function_exported?(AshGraphLaw.Reactor.Hooks, :run, 3)
    assert Reactor.Step in (AshGraphLaw.Reactor.Hooks.module_info(:attributes)[:behaviour] || [])
  end

  test "Hooks step fires the self-monitoring hook through the real engine" do
    server = start_host!([])
    pack = fixture!("packs/self-monitoring-pack/hook.ttl")
    data = fixture!("packs/self-monitoring-pack/fixtures/session-real-broad-topic.ttl")

    assert {:ok, %AshGraphLaw.Result.Hooks{firings: firings, quads: quads}} =
             Reactor.run(HooksReactor, %{pack: pack, data: data, server: server})

    assert is_list(firings) and length(firings) == 3
    assert is_integer(quads) and quads > 0
  end

  test "Hooks step returns a typed Refusal for an unparseable pack" do
    server = start_host!([])
    bad = %{"text" => "this is not turtle {{{", "dialect" => "turtle"}

    assert {:error, error} = Reactor.run(HooksReactor, %{pack: bad, data: bad, server: server})
    assert refusal_in(error)
  end

  test "Capability step runs a typed op named by option :op" do
    server = start_host!([])

    assert {:ok, %AshGraphLaw.Result.Sniff{dialect: dialect}} =
             Reactor.run(SniffReactor, %{text: "<urn:a> <urn:b> <urn:c> .", server: server})

    assert is_binary(dialect)
  end

  test "Capability step refuses an op that is not in the registry" do
    assert {:error, %Refusal{code: :unknown_capability}} =
             AshGraphLaw.Reactor.Capability.run(%{}, %{}, op: "no_such_op")

    assert {:error, %Refusal{code: :unknown_capability}} =
             AshGraphLaw.Reactor.Capability.run(%{}, %{}, [])
  end

  test "Hooks step refuses missing arguments" do
    assert {:error, %Refusal{code: :invalid_capability_request, details: %{"missing" => ["data"]}}} =
             AshGraphLaw.Reactor.Hooks.run(%{pack: "x"}, %{}, [])
  end

  # Reactor wraps step errors in its own error containers; find the Refusal inside.
  defp refusal_in(%Refusal{}), do: true

  defp refusal_in(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &refusal_in/1)
  defp refusal_in(%{error: error}), do: refusal_in(error)
  defp refusal_in(_), do: false
end
