# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.OpExamplesDriverTest do
  @moduledoc """
  Drives EVERY example of `priv/graphlaw/op-examples.json` through the typed API against the
  REAL engine and asserts the declared outcome.

  An example is a raw engine request. The typed layer validates client-side first, so a request
  that omits a required field is refused `:invalid_capability_request` before the engine sees it;
  the engine's own refusal of the identical raw request is asserted next to it. A request the
  client normalizes (a bare string for a data_spec) is compared with the engine's answer to the
  normalized request instead of the original.
  """
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.{Admitted, Refusal}

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  test "positive control: the file has every op, ok examples first, and one positive control per non-law op" do
    examples = examples()["examples"]
    assert examples != []

    for op <- op_names() do
      mine = Enum.filter(examples, &(&1["op"] == op))
      assert Enum.any?(mine, &(&1["outcome"] == "ok")), "#{op} has no ok example"
      assert hd(mine)["outcome"] == "ok", "#{op}: an ok example must come first"

      if op != "capabilities",
        do: assert(Enum.any?(mine, &(&1["outcome"] == "refused")), "#{op} has no refused example")

      assert Enum.any?(mine, & &1["positive_control"]), "#{op} has no positive control"
    end
  end

  test "every example reproduces through the typed API", %{opts: opts} do
    for example <- examples()["examples"] do
      op = example["op"]
      args = args_of(example)

      case built(op, args) do
        {:error, %Refusal{} = client} ->
          assert example["outcome"] == "refused", "#{example["id"]}: ok example refused client-side: #{inspect(client)}"
          assert client.code == :invalid_capability_request, example["id"]
          assert client.raw == nil, example["id"]
          assert {:error, %Refusal{code: :invalid_capability_request}} = typed(op, args, opts), example["id"]

          assert {:error, %Refusal{} = engine} = AshGraphLaw.call(example["request"], opts), example["id"]
          assert engine.kind == example["refusal_kind"], example["id"]

        {:ok, request} ->
          assert_engine_path(example, request, opts)
      end
    end
  end

  test "every refused example, whichever layer refuses it, is a typed refusal with the declared kind or client error",
       %{
         opts: opts
       } do
    for example <- examples()["examples"], example["outcome"] == "refused" do
      assert {:error, %Refusal{} = refusal} = typed(example["op"], args_of(example), opts), example["id"]
      assert refusal.code in [:invalid_capability_request, expected_code(example["refusal_code"])], example["id"]
      assert refusal.code in Refusal.codes(), example["id"]
    end
  end

  defp assert_engine_path(example, request, opts) do
    op = example["op"]
    id = example["id"]
    args = args_of(example)
    raw = AshGraphLaw.call(request, opts)
    normalized? = request != example["request"]

    case {example["outcome"], raw, typed(op, args, opts)} do
      {"ok", {:ok, raw_map}, {:ok, typed_struct}} ->
        assert typed_struct.raw == raw_map, id
        assert raw_map["ok"] == true, id
        if op == "law", do: assert(%Admitted{} = typed_struct, id)

      {"refused", {:error, %Refusal{} = engine}, {:error, %Refusal{} = refusal}} ->
        assert refusal.code == engine.code, id
        assert refusal.kind == engine.kind, id

        unless normalized? do
          assert refusal.code == expected_code(example["refusal_code"]), id
          assert refusal.kind == example["refusal_kind"], id
        end

      other ->
        flunk("#{id}: outcome #{example["outcome"]} not reproduced: #{inspect(other, limit: 8)}")
    end
  end
end
