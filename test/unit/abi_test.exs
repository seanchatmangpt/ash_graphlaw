# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.ABITest do
  use ExUnit.Case, async: true

  import Bitwise

  alias AshGraphLaw.ABI
  alias AshGraphLaw.Refusal

  @two_64 1 <<< 64
  @limit 16 * 1024 * 1024

  describe "version/0" do
    test "is ABI 1 (the GraphLaw v26.9.29 wasm ABI)" do
      assert ABI.version() == 1
    end
  end

  describe "unpack_result/1" do
    test "positive control: splits a packed u64 into {ptr, len} (high 32 bits, low 32 bits)" do
      assert ABI.unpack_result(1024 <<< 32 ||| 77) == {1024, 77}
    end

    test "a zero length and a zero pointer survive" do
      assert ABI.unpack_result(0) == {0, 0}
      assert ABI.unpack_result(5) == {0, 5}
      assert ABI.unpack_result(9 <<< 32) == {9, 0}
    end

    test "the largest pointer/length pair unpacks exactly" do
      assert ABI.unpack_result(0xFFFF_FFFF <<< 32 ||| 0xFFFF_FFFF) == {0xFFFF_FFFF, 0xFFFF_FFFF}
    end

    test "a negative signed i64 (wasm returns i64) is the same result as its u64 value" do
      ptr = 0x8000_0010
      len = 4096
      unsigned = ptr <<< 32 ||| len
      signed = unsigned - @two_64

      assert signed < 0
      assert ABI.unpack_result(unsigned) == {ptr, len}
      assert ABI.unpack_result(signed) == {ptr, len}
    end

    test "the most negative i64 unpacks as pointer 0x80000000, length 0" do
      assert ABI.unpack_result(-(1 <<< 63)) == {0x8000_0000, 0}
    end
  end

  describe "encode_request/1" do
    test "positive control: encodes a request map to JSON that decodes back to the same map" do
      request = %{"op" => "law", "data" => %{"text" => "<a> <b> <c> .", "dialect" => "ntriples"}}

      assert {:ok, binary} = ABI.encode_request(request)
      assert Jason.decode!(binary) == request
    end

    test "encoding is deterministic for equal inputs" do
      request = %{"op" => "capabilities", "x" => [1, 2, 3]}
      assert ABI.encode_request(request) == ABI.encode_request(request)
    end

    test "text that is not valid UTF-8 is :invalid_encoding, never :invalid_json, and is not echoed" do
      # positive control: the same request shape with valid text encodes
      assert {:ok, _} = ABI.encode_request(%{"op" => "sniff", "text" => "valid"})

      for bad <- [<<0xFF>>, <<0xFF, 0xFE, 0xFD, 0x80>>, "ok" <> <<0xC3>>] do
        assert {:error, %Refusal{code: :invalid_encoding, class: :refused_structure} = refusal} =
                 ABI.encode_request(%{"op" => "sniff", "text" => bad, "nested" => %{"deep" => [bad]}})

        refute refusal.message =~ "ok"
        assert refusal.details == %{}
      end
    end

    test "a term that cannot be JSON-encoded at all is still :invalid_json" do
      assert {:error, %Refusal{code: :invalid_json}} = ABI.encode_request(%{"op" => "law", "data" => self()})
    end

    test "a request whose encoding exceeds 16 MiB is refused as :resource_limit" do
      request = %{"op" => "capabilities", "pad" => String.duplicate("a", @limit)}

      assert {:error, %Refusal{code: :resource_limit, class: :blocked_resource}} =
               ABI.encode_request(request)
    end

    test "a request comfortably under 16 MiB is accepted (boundary control for the refusal above)" do
      request = %{"op" => "capabilities", "pad" => String.duplicate("a", div(@limit, 2))}
      assert {:ok, binary} = ABI.encode_request(request)
      assert byte_size(binary) < @limit
    end
  end

  describe "decode_response/1" do
    test "positive control: decodes a JSON object response" do
      assert {:ok, %{"ok" => true, "abi_version" => 1}} = ABI.decode_response(~s({"ok":true,"abi_version":1}))
    end

    test "an engine refusal response (ok: false) is still a successfully decoded map" do
      body = ~s({"ok":false,"error":{"kind":"Refused","message":"nope"}})
      assert {:ok, %{"ok" => false, "error" => %{"message" => "nope"}}} = ABI.decode_response(body)
    end

    test "non-JSON bytes are refused as :invalid_json" do
      assert {:error, %Refusal{code: :invalid_json, class: :refused_structure}} = ABI.decode_response("not json at all")
    end

    test "an empty response is refused as :invalid_json" do
      assert {:error, %Refusal{code: :invalid_json}} = ABI.decode_response("")
    end

    test "a truncated JSON document is refused as :invalid_json" do
      assert {:error, %Refusal{code: :invalid_json}} = ABI.decode_response(~s({"ok":tru))
    end
  end
end
