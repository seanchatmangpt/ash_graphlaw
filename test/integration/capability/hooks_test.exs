# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.HooksTest do
  @moduledoc """
  Typed `hooks` against the REAL engine, plus the legacy root `hooks/3`, which keeps its own
  untyped return shape while the typed equivalent lives only at `Capability.API.hooks/2`.
  """
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Result.Hooks, as: Result

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "an inline pack fires and derives a B for the A", %{opts: opts} do
      result = assert_typed_matches_raw("hooks", args_of(example!("hooks.inline-pack")), opts)
      assert %Result{id: id, rounds: rounds, quads: quads, nquads: nquads, firings: firings} = result
      assert is_binary(id) and is_integer(rounds) and is_integer(quads)
      assert nquads =~ "https://e/B"
      assert [firing | _] = firings
      assert is_map(firing) and not is_struct(firing)
    end

    test "a pack that matches nothing fires nothing", %{opts: opts} do
      assert {:ok, %Result{firings: []}} = API.hooks(args_of(example!("hooks.no-match")), opts)
    end

    test "the legacy root hooks/3 is unchanged and returns raw for the same request", %{opts: opts} do
      request = example!("hooks.inline-pack")["request"]
      assert {:ok, %Result{raw: raw}} = API.hooks(args_of(example!("hooks.inline-pack")), opts)
      assert {:ok, legacy} = AshGraphLaw.hooks(request["data"], request["pack"], opts)
      assert legacy == raw
    end
  end

  describe "refusals" do
    test "an unsupported hook kind is an engine refusal", %{opts: opts} do
      assert_refusal(API.hooks(args_of(example!("hooks.unsupported-kind-refused")), opts), :engine_refused,
        kind: "EngineRejected"
      )
    end

    test "missing pack is refused client-side", %{opts: opts} do
      example = example!("hooks.missing-pack-refused")
      refusal = assert_refusal(API.hooks(args_of(example), opts), :invalid_capability_request)
      assert refusal.details["missing"] == ["pack"]
    end
  end
end
