# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits adversarial courts.

defmodule AshGraphLaw.Adversarial.MemoryBombTest do
  @moduledoc """
  Adversarial court for hostile request sizes and encodings at the host boundary.

  Non-UTF-8 payloads, requests above the 16 MiB ABI cap and JSON nested beyond the engine's
  depth limit are refused with typed refusals, and the same host instance keeps serving
  afterwards. The pure ABI encoder is covered without the engine; the host tests run
  against the real pinned engine under `:wasm`.
  """

  use AshGraphLaw.Test.Case, async: true

  alias AshGraphLaw.{ABI, Host, Refusal}

  @limit 16 * 1024 * 1024

  defp deep(depth), do: Enum.reduce(1..depth, "leaf", fn _, acc -> %{"a" => acc} end)

  describe "ABI encoder (no engine)" do
    test "positive control: an ordinary request encodes" do
      assert {:ok, body} = ABI.encode_request(%{"op" => "capabilities"})
      assert Jason.decode!(body) == %{"op" => "capabilities"}
    end

    test "a request above the 16 MiB cap is a :resource_limit refusal that reports its size" do
      request = %{"op" => "sniff", "text" => String.duplicate("a", @limit + 1)}

      assert {:error, %Refusal{code: :resource_limit, class: :blocked_resource, details: details}} =
               ABI.encode_request(request)

      assert details.limit == @limit
      assert details.bytes > @limit
    end

    test "a request just under the cap still encodes" do
      request = %{"op" => "sniff", "text" => String.duplicate("a", @limit - 1024)}
      assert {:ok, body} = ABI.encode_request(request)
      assert byte_size(body) <= @limit
    end

    test "non-UTF-8 text is refused as :invalid_encoding, never raised" do
      assert {:ok, _} = ABI.encode_request(%{"op" => "sniff", "text" => "valid é"})

      for bad <- [<<0xFF>>, <<0xFF, 0xFE, 0xFD>>, "ok" <> <<0xC3>>, <<0xED, 0xA0, 0x80>>] do
        assert {:error, %Refusal{code: :invalid_encoding, class: :refused_structure}} =
                 ABI.encode_request(%{"op" => "sniff", "text" => bad})
      end
    end
  end

  describe "host boundary (real engine)" do
    @describetag :wasm

    setup do
      host = start_host!(name: nil)
      # positive control shared by every test: the host serves before the attack
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities"})
      %{host: host}
    end

    defp assert_still_serving(host) do
      assert Process.alive?(host)
      assert Host.available?(host, 10_000)
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities"})
      assert {:ok, size} = Host.memory_size(host)
      assert size <= AshGraphLaw.WasmConfig.limits([]).memory_limit_bytes
    end

    test "non-UTF-8 text is refused at the boundary and the host stays available", %{host: host} do
      for bad <- [<<0xFF>>, <<0xFF, 0xFE, 0xFD>>, "ok" <> <<0xC3>>] do
        assert {:error, %Refusal{code: code, class: :refused_structure}} =
                 Host.request(host, %{"op" => "sniff", "text" => bad})

        assert code == :invalid_encoding
      end

      assert_still_serving(host)
    end

    test "a request above 16 MiB is refused and the host stays available", %{host: host} do
      request = %{"op" => "sniff", "text" => String.duplicate("a", @limit + 1)}

      assert {:error, %Refusal{code: :resource_limit, class: :blocked_resource}} = Host.request(host, request)
      assert_still_serving(host)
    end

    test "JSON nested beyond the engine depth limit is a :resource_limit refusal from the engine", %{host: host} do
      # control: shallow nesting is served
      assert {:ok, %{"ok" => true}} = Host.request(host, %{"op" => "capabilities", "junk" => deep(8)})

      assert {:error, %Refusal{code: :resource_limit, class: :blocked_resource, details: details}} =
               AshGraphLaw.call(%{"op" => "capabilities", "junk" => deep(200)}, server: host)

      assert details["limit"] == "json_depth" or details[:limit] == "json_depth"
      assert_still_serving(host)
    end

    test "repeated hostile requests do not grow the engine beyond its memory limit", %{host: host} do
      for _ <- 1..5 do
        assert {:error, %Refusal{code: :resource_limit}} =
                 Host.request(host, %{"op" => "sniff", "text" => String.duplicate("b", @limit + 1)})

        assert {:error, %Refusal{}} = Host.request(host, %{"op" => "sniff", "text" => <<0xFF>>})
      end

      assert_still_serving(host)
    end
  end
end
