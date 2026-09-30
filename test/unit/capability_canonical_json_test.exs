# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Unit.CapabilityCanonicalJSONTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago suite for the canonical JSON helper.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Capability.CanonicalJSON

  # Vectors computed with python3:
  #   json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
  @nested %{
    "z" => [1, %{"b" => nil, "a" => true}, "x"],
    "a" => %{"kéy" => "café ☃ 😀", "Z" => 0},
    "m" => -42,
    "esc" => "q\"b\\s/\n\t\r\b\f\u0001\u001f\u007f"
  }
  @nested_canonical "{\"a\":{\"Z\":0,\"kéy\":\"café ☃ 😀\"},\"esc\":\"q\\\"b\\\\s/\\n\\t\\r\\b\\f\\u0001\\u001f\u007f\",\"m\":-42,\"z\":[1,{\"a\":true,\"b\":null},\"x\"]}"
  @nested_sha "sha256:f19b2d761706fb59dc916a77f2e2faedbdacfb5fec79abe2b8b69e5540443e08"

  @registry %{
    "abi_version" => 1,
    "registry_sha256" => "sha256:dead",
    "ops" => ["capabilities", "sniff"],
    "n" => %{"b" => 2, "a" => 1}
  }
  @registry_digest "sha256:fc9009ad3b9add8ed2478fa03a4f0d1c9f7d05cdcadd5ff3e0bec74835416fea"

  @surface_sha "sha256:2135437c74048c17d6e8a227e5e9822e05c1d9a813b721192ab4388657a88475"

  describe "positive control" do
    test "encode sorts keys and matches the python vector byte for byte" do
      assert CanonicalJSON.encode(@nested) == @nested_canonical
      assert CanonicalJSON.sha256(@nested) == @nested_sha
    end
  end

  describe "encode/1 per closed scalar type" do
    for {input, expected} <- [
          {nil, "null"},
          {true, "true"},
          {false, "false"},
          {0, "0"},
          {-7, "-7"},
          {12_345_678_901_234_567_890, "12345678901234567890"},
          {"", ~s("")},
          {"plain", ~s("plain")},
          {"a\"b", ~S("a\"b")},
          {"a\\b", ~S("a\\b")},
          {"a/b", ~s("a/b")},
          {"\b\t\n\f\r", ~S("\b\t\n\f\r")},
          {<<0>>, ~S("\u0000")},
          {<<31>>, ~S("\u001f")},
          {<<127>>, <<?", 127, ?">>},
          {"é☃😀", ~s("é☃😀")},
          {[], "[]"},
          {%{}, "{}"},
          {[3, 1, 2], "[3,1,2]"},
          {%{b: 1, a: 2}, ~s({"a":2,"b":1})},
          {%{"b" => [], "a" => %{}}, ~s({"a":{},"b":[]})}
        ] do
      test "encodes #{inspect(input)}" do
        assert CanonicalJSON.encode(unquote(Macro.escape(input))) == unquote(expected)
      end
    end

    test "keys sort by byte order, not codepoint locale" do
      assert CanonicalJSON.encode(%{"b" => 1, "B" => 2, "é" => 3, "a" => 4}) ==
               ~s({"B":2,"a":4,"b":1,"é":3})
    end

    test "floats and foreign terms raise ArgumentError" do
      assert_raise ArgumentError, fn -> CanonicalJSON.encode(1.5) end
      assert_raise ArgumentError, fn -> CanonicalJSON.encode(%{"a" => [1.0]}) end
      assert_raise ArgumentError, fn -> CanonicalJSON.encode({:tuple}) end
      assert_raise ArgumentError, fn -> CanonicalJSON.encode(%{1 => "int key"}) end
    end

    test "output is valid JSON that decodes back to the input" do
      assert @nested |> CanonicalJSON.encode() |> Jason.decode!() == @nested
    end
  end

  describe "digests" do
    test "digest/1 drops registry_sha256 and matches the python vector" do
      assert CanonicalJSON.digest(@registry) == @registry_digest
    end

    test "digest/1 ignores the stored value of registry_sha256 and accepts an atom key" do
      other = Map.put(@registry, "registry_sha256", "sha256:beef")
      assert CanonicalJSON.digest(other) == @registry_digest
      assert CanonicalJSON.digest(Map.delete(@registry, "registry_sha256")) == @registry_digest
      assert CanonicalJSON.digest(Map.put(@registry, :registry_sha256, "x")) == @registry_digest
    end

    test "surface_digest/1 of a capabilities-shaped response matches the python vector" do
      response = %{
        "ok" => true,
        "abi" => 1,
        "abi_version" => 1,
        "crate" => "graphlaw",
        "ops" => ["capabilities", "sniff"],
        "rdf_dialects" => ["turtle", "ntriples"],
        "other_dialects" => ["n3"]
      }

      assert CanonicalJSON.surface_digest(response) == @surface_sha
    end

    test "surface_digest/1 accepts op and dialect maps and atom keys" do
      registry = %{
        "abi_version" => 1,
        "ops" => [%{"name" => "capabilities", "order" => 1}, %{"name" => "sniff", "order" => 2}],
        "rdf_dialects" => [%{"name" => "turtle"}, %{"name" => "ntriples"}],
        "other_dialects" => [%{"name" => "n3"}]
      }

      atom_registry = %{
        abi_version: 1,
        ops: [%{name: "capabilities"}, %{name: "sniff"}],
        rdf_dialects: ["turtle", "ntriples"],
        other_dialects: ["n3"]
      }

      assert CanonicalJSON.surface_digest(registry) == @surface_sha
      assert CanonicalJSON.surface_digest(atom_registry) == @surface_sha
    end

    test "surface_digest/1 never raises on an empty or malformed source" do
      assert "sha256:" <> hex = CanonicalJSON.surface_digest(%{})
      assert byte_size(hex) == 64
      assert is_binary(CanonicalJSON.surface_digest(%{"ops" => "nope", "rdf_dialects" => 3}))
    end

    test "surface digest changes when an op is added" do
      base = %{"abi_version" => 1, "ops" => ["a"], "rdf_dialects" => [], "other_dialects" => []}
      refute CanonicalJSON.surface_digest(base) == CanonicalJSON.surface_digest(%{base | "ops" => ["a", "b"]})
    end
  end

  describe "cross-language conformance with the graphlaw registry" do
    @registry_path Path.expand("../../../graphlaw/registry/capability-registry.json", __DIR__)

    test "digest of the emitted registry equals its stored registry_sha256 (when present)" do
      case File.read(@registry_path) do
        {:ok, json} ->
          registry = Jason.decode!(json)
          assert CanonicalJSON.digest(registry) == registry["registry_sha256"]
          assert CanonicalJSON.surface_digest(registry) == registry["surface_sha256"]

        {:error, _} ->
          # The python vectors above carry the conformance obligation until the registry is emitted.
          assert CanonicalJSON.digest(@registry) == @registry_digest
      end
    end
  end
end
