# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.DeterminismTest do
  @moduledoc """
  Same input, same real engine: identical state ids and identical evidence digest.
  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{Admitted, Evidence}

  @moduletag :wasm

  @data "<urn:a:C> <http://www.w3.org/2000/01/rdf-schema#subClassOf> <urn:a:D> .\n<urn:a:x> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:a:C> .\n"

  defp run(server) do
    AshGraphLaw.law(%{"text" => @data, "dialect" => "ntriples"}, [%{"step" => "rdfs"}], server: server)
  end

  defp digest_of(admitted) do
    input_digest = Base.encode16(:crypto.hash(:sha256, @data), case: :lower)
    Evidence.new(:determinism, admitted, input_digest, []) |> Evidence.digest()
  end

  test "identical law requests yield identical state ids, receipts and evidence digest" do
    server = start_host!([])
    assert {:ok, %Admitted{} = one} = run(server)
    assert {:ok, %Admitted{} = two} = run(server)

    assert one.states == two.states
    assert [_, _] = one.states
    assert one.receipts == two.receipts
    assert one.nquads == two.nquads

    d1 = digest_of(one)
    assert d1 == digest_of(two)
    assert String.match?(d1, ~r/\A[0-9a-f]{64}\z/)
  end

  test "determinism holds across independent host instances" do
    a = start_host!([])
    b = start_host!([])
    assert {:ok, %Admitted{} = ra} = run(a)
    assert {:ok, %Admitted{} = rb} = run(b)
    assert ra.states == rb.states
    assert digest_of(ra) == digest_of(rb)
  end

  test "different input changes the state ids and the evidence digest (control against vacuity)" do
    server = start_host!([])
    assert {:ok, %Admitted{} = base} = run(server)

    other = "<urn:a:E> <http://www.w3.org/2000/01/rdf-schema#subClassOf> <urn:a:F> .\n"

    assert {:ok, %Admitted{} = changed} =
             AshGraphLaw.law(%{"text" => other, "dialect" => "ntriples"}, [%{"step" => "rdfs"}], server: server)

    refute base.states == changed.states

    refute digest_of(base) ==
             Evidence.new(:determinism, changed, Base.encode16(:crypto.hash(:sha256, other), case: :lower), [])
             |> Evidence.digest()
  end
end
