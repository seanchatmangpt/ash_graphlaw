# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack emits adversarial courts.

defmodule AshGraphLaw.Adversarial.HostileEncodingTest do
  @moduledoc """
  Adversarial court for hostile text where it enters the ABI: invalid UTF-8 hidden at any depth
  of a request (nested maps, lists, map keys, huge strings) is refused `:invalid_encoding`
  (class `:refused_structure`) before any byte reaches the engine, and non-encodable terms are
  a distinct `:invalid_json` refusal. The pure encoder is covered without the engine; the
  `:wasm` part drives the same requests through the real ABI and shows the engine's memory did
  not grow for a refused request.
  """

  use AshGraphLaw.Test.Case, async: true

  alias AshGraphLaw.{ABI, Host, Refusal}

  @bad [<<0xFF>>, <<0xC0, 0x80>>, <<0xED, 0xA0, 0x80>>, <<0xF8, 0x88, 0x80, 0x80, 0x80>>, "ok" <> <<0xE2, 0x82>>]

  defp nest(payload, 0), do: payload
  defp nest(payload, n), do: nest(%{"k" => [payload, "fine"]}, n - 1)

  describe "ABI encoder (no engine)" do
    test "positive control: valid multibyte text at depth encodes and round-trips" do
      request = %{"op" => "sniff", "text" => nest("héllo ✓ 😀", 5)}
      assert {:ok, body} = ABI.encode_request(request)
      assert Jason.decode!(body) == request
    end

    test "invalid UTF-8 is refused :invalid_encoding at every nesting depth" do
      for bad <- @bad, depth <- [0, 1, 5, 20] do
        assert {:error, %Refusal{code: :invalid_encoding, class: :refused_structure}} =
                 ABI.encode_request(%{"op" => "sniff", "text" => nest(bad, depth)})
      end
    end

    test "invalid UTF-8 in a map key or a list element is refused too" do
      assert {:error, %Refusal{code: :invalid_encoding}} = ABI.encode_request(%{"op" => "sniff", <<0xFF>> => 1})

      assert {:error, %Refusal{code: :invalid_encoding}} =
               ABI.encode_request(%{"op" => "n3", "rules" => ["ok", <<0xFF>>]})
    end

    test "the refusal never echoes the offending bytes" do
      assert {:error, %Refusal{} = refusal} = ABI.encode_request(%{"op" => "sniff", "text" => "secret-" <> <<0xFF>>})
      refute inspect(refusal) =~ "secret-"
    end

    test "a valid megabyte string next to nothing invalid is not refused (no over-blocking)" do
      assert {:ok, body} = ABI.encode_request(%{"op" => "sniff", "text" => String.duplicate("é", 512 * 1024)})
      assert byte_size(body) > 1_000_000
    end

    test "a non-encodable term is :invalid_json, distinct from :invalid_encoding" do
      assert {:error, %Refusal{code: :invalid_json}} = ABI.encode_request(%{"op" => "sniff", "text" => {:a, :tuple}})
      assert {:error, %Refusal{code: :invalid_json}} = ABI.encode_request(%{"op" => "sniff", "text" => self()})
    end

    test "invalid UTF-8 is refused before the size cap is applied to it" do
      huge_bad = String.duplicate("a", ABI.max_request_bytes() + 1) <> <<0xFF>>
      assert {:error, %Refusal{code: code}} = ABI.encode_request(%{"op" => "sniff", "text" => huge_bad})
      assert code == :invalid_encoding
    end
  end

  describe "through the real ABI" do
    @describetag :wasm

    test "hidden invalid UTF-8 is refused, engine memory does not grow, the host keeps serving" do
      host = start_host!(name: nil)
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities"})
      assert {:ok, before} = Host.memory_size(host)

      for bad <- @bad, depth <- [0, 3, 12] do
        assert {:error, %Refusal{code: :invalid_encoding, class: :refused_structure}} =
                 Host.request(host, %{"op" => "sniff", "text" => nest(bad, depth)})
      end

      assert {:ok, ^before} = Host.memory_size(host)
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities"})
      assert {:ok, %{recycles: 0}} = Host.info(host)
    end
  end
end
