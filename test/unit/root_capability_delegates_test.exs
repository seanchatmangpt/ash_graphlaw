# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.RootCapabilityDelegatesTest do
  @moduledoc """
  The generated typed delegates on the root `AshGraphLaw` API (`parse/2`, `sparql/2`, ...) run
  against the REAL vendored GraphLaw engine, and the legacy `sniff/3` / `capabilities/1` shapes
  stay unchanged. No mocks, no stubs.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Result

  @moduletag :wasm

  @turtle "@prefix ex: <http://example.org/> .\nex:a ex:p ex:b .\nex:b ex:p ex:c .\n"

  setup do
    if require_engine!() do
      {:ok, server: start_host!()}
    else
      :ok
    end
  end

  test "positive control: parse/2 returns a typed Result.Parse with the raw response preserved",
       %{server: server} do
    assert {:ok, %Result.Parse{quads: quads, raw: raw}} =
             AshGraphLaw.parse(%{text: @turtle, dialect: "turtle"}, server: server)

    assert is_integer(quads) and quads >= 2
    assert %{"ok" => true} = raw
    assert raw["quads"] == quads
  end

  test "sparql/2 select decodes to kind :solutions", %{server: server} do
    args = %{
      data: %{text: @turtle, dialect: "turtle"},
      query: "SELECT ?s WHERE { ?s <http://example.org/p> ?o }"
    }

    assert {:ok, %Result.Sparql{kind: :solutions, variables: ["s"], rows: rows}} =
             AshGraphLaw.sparql(args, server: server)

    assert length(rows) == 2
  end

  test "a missing required argument is a client-side typed refusal", %{server: server} do
    assert {:error, %AshGraphLaw.Refusal{code: :invalid_capability_request}} =
             AshGraphLaw.parse(%{dialect: "turtle"}, server: server)
  end

  test "the bang form raises AshGraphLaw.Error.Refused on refusal", %{server: server} do
    assert_raise Refused, fn -> AshGraphLaw.parse!(%{dialect: "turtle"}, server: server) end
    assert %Result.Parse{} = AshGraphLaw.parse!(%{text: @turtle, dialect: "turtle"}, server: server)
  end

  test "legacy sniff/3 and capabilities/1 keep their untyped map shapes", %{server: server} do
    assert {:ok, %{"ok" => true, "dialect" => dialect, "engine" => _}} =
             AshGraphLaw.sniff(@turtle, nil, server: server)

    assert is_binary(dialect)

    assert {:ok, %{"ok" => true, "abi" => 1, "ops" => ops}} =
             AshGraphLaw.capabilities(server: server)

    assert "parse" in ops and "law" in ops
  end
end
