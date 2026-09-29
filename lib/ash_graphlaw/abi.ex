# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.ABI do
  @moduledoc """
  Pure codec for GraphLaw ABI 1.

  This module holds no process state and makes no Wasmex calls. `AshGraphLaw.Host` owns
  linear-memory operations (`gl_alloc`, write, `gl_call`, read, `gl_free`); this module
  only converts between Elixir terms and the bytes and packed integers that cross the
  boundary.

  ## Packed result

  `gl_call` returns one 64-bit integer: the high 32 bits are the response pointer and
  the low 32 bits are the response length. Hosts that surface the value as a signed
  `i64` may hand back a negative integer; `unpack_result/1` normalizes it by adding
  `2^64` before splitting.

  ## Limits

  Requests larger than #{16 * 1_048_576} bytes (16 MiB) are refused with
  `:resource_limit` before any memory is allocated in the engine.
  """

  import Bitwise

  alias AshGraphLaw.Refusal

  @abi_version 1
  @u64 0x1_0000_0000_0000_0000
  @u32_mask 0xFFFF_FFFF
  @max_request_bytes 16 * 1_048_576

  @doc "The ABI version this build of the library speaks."
  @spec version() :: pos_integer()
  def version, do: @abi_version

  @doc "Maximum encoded request size in bytes."
  @spec max_request_bytes() :: pos_integer()
  def max_request_bytes, do: @max_request_bytes

  @doc """
  Splits a packed `gl_call` result into `{ptr, len}`.

  Negative integers (a signed `i64` view of the same 64 bits) are normalized by adding
  `2^64`.

  ## Examples

      iex> AshGraphLaw.ABI.unpack_result(Bitwise.bsl(123, 32) + 45)
      {123, 45}

      iex> AshGraphLaw.ABI.unpack_result(-1)
      {4_294_967_295, 4_294_967_295}
  """
  @spec unpack_result(integer()) :: {non_neg_integer(), non_neg_integer()}
  def unpack_result(packed) when is_integer(packed) do
    unsigned = if packed < 0, do: packed + @u64, else: packed
    {unsigned >>> 32 &&& @u32_mask, unsigned &&& @u32_mask}
  end

  @doc """
  Encodes a request map (string keys) as JSON bytes.

  Returns `{:error, %Refusal{code: :resource_limit}}` above the 16 MiB cap and
  `{:error, %Refusal{code: :invalid_json}}` when the term cannot be JSON-encoded, and
  `{:error, %Refusal{code: :invalid_encoding}}` when a string in it is not valid UTF-8.
  """
  @spec encode_request(map()) :: {:ok, binary()} | {:error, Refusal.t()}
  def encode_request(request) when is_map(request) do
    case safe_encode(request) do
      {:ok, payload} when byte_size(payload) > @max_request_bytes ->
        {:error,
         Refusal.new(:resource_limit, "request exceeds the 16 MiB ABI limit", %{
           bytes: byte_size(payload),
           limit: @max_request_bytes
         })}

      {:ok, payload} ->
        {:ok, payload}

      :invalid_encoding ->
        {:error, Refusal.new(:invalid_encoding, "request contains text that is not valid UTF-8")}

      {:error, message} ->
        {:error, Refusal.new(:invalid_json, "request is not JSON-encodable: " <> message)}
    end
  end

  @doc """
  Decodes response bytes into a map.

  Non-JSON bytes yield `:invalid_json`; JSON that is not an object yields
  `:malformed_response`. Both `"ok": true` and `"ok": false` bodies decode to `{:ok, map}`;
  classifying them is the caller's job.
  """
  @spec decode_response(binary()) :: {:ok, map()} | {:error, Refusal.t()}
  def decode_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = response} ->
        {:ok, response}

      {:ok, _other} ->
        {:error, Refusal.new(:malformed_response, "GraphLaw response is not a JSON object")}

      {:error, reason} ->
        {:error, Refusal.new(:invalid_json, Exception.message(reason), %{bytes: byte_size(body)})}
    end
  end

  defp safe_encode(request) do
    case Jason.encode(request) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> classify_encode_error(reason)
    end
  rescue
    error -> classify_encode_error(error)
  end

  # Jason rejects a string that is not valid UTF-8 before any byte reaches the engine; that is an
  # encoding refusal, not a JSON-shape one. The message (which would quote the offending text) is
  # deliberately not propagated for it.
  defp classify_encode_error(%Jason.EncodeError{message: "invalid byte " <> _rest}), do: :invalid_encoding
  defp classify_encode_error(error), do: {:error, Exception.message(error)}
end
