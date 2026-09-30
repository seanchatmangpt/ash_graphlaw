# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.ABITest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite; real ABI codec, no doubles.
  use AshGraphLaw.Test.PropertyCase, async: true

  import Bitwise

  alias AshGraphLaw.ABI

  describe "positive controls" do
    test "a known request encodes, decodes back, and a known packed result splits" do
      assert {:ok, bytes} = ABI.encode_request(%{"op" => "capabilities"})
      assert {:ok, %{"op" => "capabilities"}} = ABI.decode_response(bytes)
      assert ABI.unpack_result(bsl(123, 32) + 45) == {123, 45}
      assert ABI.unpack_result(-1) == {0xFFFF_FFFF, 0xFFFF_FFFF}
    end
  end

  describe "encode_request/1 and decode_response/1" do
    property "round trip: decode(encode(map)) is the JSON-normalized map" do
      check all(map <- json_map(), max_runs: max_runs()) do
        assert {:ok, bytes} = ABI.encode_request(map)
        assert is_binary(bytes)
        assert {:ok, decoded} = ABI.decode_response(bytes)
        assert decoded == map |> Jason.encode!() |> Jason.decode!()
      end
    end

    property "encoding is deterministic" do
      check all(map <- json_map(), max_runs: max_runs()) do
        assert ABI.encode_request(map) == ABI.encode_request(map)
      end
    end

    property "random binaries never crash decode_response/1: ok map or typed refusal" do
      check all(bytes <- random_binary(), max_runs: max_runs()) do
        case ABI.decode_response(bytes) do
          {:ok, %{} = map} ->
            assert {:ok, ^map} = Jason.decode(bytes)

          {:error, %Refusal{code: code, class: class}} ->
            assert code in [:invalid_json, :malformed_response]
            assert class == :refused_structure
        end
      end
    end

    property "JSON that is not an object is :malformed_response, not a crash" do
      check all(
              value <- one_of([integer(), boolean(), text(), list_of(integer(), max_length: 3), constant(nil)]),
              max_runs: max_runs()
            ) do
        assert {:error, %Refusal{code: :malformed_response}} = value |> Jason.encode!() |> ABI.decode_response()
      end
    end

    property "a map holding invalid UTF-8 is refused as :invalid_encoding" do
      check all(bad <- invalid_utf8(), key <- word(), max_runs: max_runs()) do
        assert {:error, %Refusal{code: :invalid_encoding, class: :refused_structure}} =
                 ABI.encode_request(%{key => bad})
      end
    end

    property "a map holding an unencodable term is a typed refusal, never a raise" do
      check all(term <- unencodable(), key <- word(), max_runs: max_runs()) do
        assert {:error, %Refusal{code: code}} = ABI.encode_request(%{key => term})
        assert code in [:invalid_json, :invalid_encoding]
      end
    end
  end

  describe "unpack_result/1" do
    property "halves are 32-bit and reassemble to the unsigned 64-bit pattern" do
      check all(packed <- packed(), max_runs: max_runs()) do
        {ptr, len} = ABI.unpack_result(packed)
        assert ptr in 0..0xFFFF_FFFF
        assert len in 0..0xFFFF_FFFF

        unsigned = if packed < 0, do: packed + 0x1_0000_0000_0000_0000, else: packed
        assert bsl(ptr, 32) + len == unsigned
      end
    end

    property "a signed view and its unsigned twin unpack identically" do
      check all(unsigned <- integer(0..0xFFFF_FFFF_FFFF_FFFF), max_runs: max_runs()) do
        signed = if unsigned >= 0x8000_0000_0000_0000, do: unsigned - 0x1_0000_0000_0000_0000, else: unsigned
        assert ABI.unpack_result(signed) == ABI.unpack_result(unsigned)
      end
    end
  end
end
