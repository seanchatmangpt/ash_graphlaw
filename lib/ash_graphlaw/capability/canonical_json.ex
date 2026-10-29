# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
# UNSUPPORTED(generator-capability): pure helper shared by every generated capability module;
# no pack template emits canonical JSON, argument coercion or response decoding.

defmodule AshGraphLaw.Capability.CanonicalJSON do
  @moduledoc """
  Canonical JSON and the registry/surface digests (the DIGEST RULE of the capability registry).

  `encode/1` emits compact JSON with object keys sorted by byte order, arrays in order,
  RFC 8259 minimal string escaping (`"` and `\\` and control characters below 0x20; the short
  forms `\\b \\t \\n \\f \\r`, lowercase `\\u00xx` otherwise; non-ASCII stays raw UTF-8) and
  integers in decimal. The bytes are identical to `serde_json` with the default (sorted) map,
  and to Python `json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False)`.

  Only strings, integers, booleans, `nil`, lists and maps are accepted. Floats, and any other
  term, raise `ArgumentError`: the digest is over canonical bytes and a float has none.
  """

  @type json :: nil | boolean() | integer() | String.t() | [json()] | %{optional(term()) => json()}

  @doc "Canonical JSON bytes of `term`."
  @spec encode(json()) :: binary()
  def encode(term), do: IO.iodata_to_binary(enc(term))

  @doc ~s|`"sha256:<hex>"` of the canonical bytes of `term`.|
  @spec sha256(json()) :: String.t()
  def sha256(term) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, encode(term)), case: :lower)
  end

  @doc ~s|`"blake3:<hex>"` of the canonical bytes of `term` (external `b3sum`).|
  @spec blake3(json()) :: String.t()
  def blake3(term) do
    path = Path.join(System.tmp_dir!(), "ash-graphlaw-canonical-#{System.unique_integer([:positive])}")

    try do
      File.write!(path, encode(term))

      case System.cmd("b3sum", [path], stderr_to_stdout: true) do
        {out, 0} ->
          "blake3:" <> (out |> String.split() |> List.first())

        {out, code} ->
          raise ArgumentError,
            message: "b3sum failed (exit #{code}): #{String.trim(out)}"
      end
    after
      File.rm(path)
    end
  end

  @doc """
  Registry digest: `blake3/1` of the registry document with the `"registry_blake3"` key removed
  (v26.10.28+ registries); registries of the `registry_sha256` era fall back to `sha256/1`.
  """
  @spec digest(map()) :: String.t()
  def digest(registry) when is_map(registry) do
    if Map.has_key?(registry, "registry_blake3") or Map.has_key?(registry, :registry_blake3) do
      registry |> Map.drop(["registry_blake3", :registry_blake3]) |> blake3()
    else
      registry |> Map.drop(["registry_sha256", :registry_sha256]) |> sha256()
    end
  end

  @doc """
  Surface digest: `blake3/1` of
  `%{"abi_version", "ops", "other_dialects", "rdf_dialects"}` extracted from a `capabilities`
  response or a registry document (string or atom keys). Op and dialect entries may be names
  or maps carrying a `name`. Absent members contribute `[]` (`abi_version` contributes `nil`).
  """
  @spec surface_digest(map()) :: String.t()
  def surface_digest(source) when is_map(source) do
    surface = %{
      "abi_version" => fetch(source, "abi_version"),
      "ops" => names(fetch(source, "ops")),
      "other_dialects" => names(fetch(source, "other_dialects")),
      "rdf_dialects" => names(fetch(source, "rdf_dialects"))
    }

    legacy? =
      (Map.has_key?(source, "surface_sha256") or Map.has_key?(source, :surface_sha256)) and
        not (Map.has_key?(source, "surface_blake3") or Map.has_key?(source, :surface_blake3))

    if legacy?, do: sha256(surface), else: blake3(surface)
  end

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key(key))
    end
  end

  defp atom_key("abi_version"), do: :abi_version
  defp atom_key("ops"), do: :ops
  defp atom_key("other_dialects"), do: :other_dialects
  defp atom_key("rdf_dialects"), do: :rdf_dialects

  defp names(list) when is_list(list), do: Enum.map(list, &name/1)
  defp names(_), do: []

  defp name(%{} = entry), do: fetch_name(entry)
  defp name(other), do: other

  defp fetch_name(entry) do
    case Map.fetch(entry, "name") do
      {:ok, value} -> value
      :error -> Map.get(entry, :name)
    end
  end

  defp enc(nil), do: "null"
  defp enc(true), do: "true"
  defp enc(false), do: "false"
  defp enc(int) when is_integer(int), do: Integer.to_string(int)
  defp enc(bin) when is_binary(bin), do: [?", escape(bin, []), ?"]

  defp enc(float) when is_float(float) do
    raise ArgumentError, "canonical JSON has no float encoding: #{inspect(float)}"
  end

  defp enc(list) when is_list(list) do
    [?[, list |> Enum.map(&enc/1) |> Enum.intersperse(?,), ?]]
  end

  defp enc(%{} = map) do
    body =
      map
      |> Enum.map(fn {key, value} -> {key_string(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, value} -> [enc(key), ?:, enc(value)] end)
      |> Enum.intersperse(?,)

    [?{, body, ?}]
  end

  defp enc(other) do
    raise ArgumentError, "canonical JSON cannot encode #{inspect(other)}"
  end

  defp key_string(key) when is_binary(key), do: key
  defp key_string(key) when is_atom(key) and not is_nil(key), do: Atom.to_string(key)

  defp key_string(key) do
    raise ArgumentError, "canonical JSON object keys must be strings or atoms: #{inspect(key)}"
  end

  defp escape(<<>>, acc), do: Enum.reverse(acc)
  defp escape(<<?", rest::binary>>, acc), do: escape(rest, [~S(\") | acc])
  defp escape(<<?\\, rest::binary>>, acc), do: escape(rest, [~S(\\) | acc])
  defp escape(<<8, rest::binary>>, acc), do: escape(rest, [~S(\b) | acc])
  defp escape(<<9, rest::binary>>, acc), do: escape(rest, [~S(\t) | acc])
  defp escape(<<10, rest::binary>>, acc), do: escape(rest, [~S(\n) | acc])
  defp escape(<<12, rest::binary>>, acc), do: escape(rest, [~S(\f) | acc])
  defp escape(<<13, rest::binary>>, acc), do: escape(rest, [~S(\r) | acc])

  defp escape(<<char, rest::binary>>, acc) when char < 0x20 do
    hex = char |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
    escape(rest, ["\\u" <> hex | acc])
  end

  defp escape(<<char, rest::binary>>, acc), do: escape(rest, [char | acc])
end
