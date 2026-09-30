# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack emits adversarial courts.

defmodule AshGraphLaw.Adversarial.ForgedLeaseEngineTest do
  @moduledoc """
  Adversarial court for leases that CLAIM `:construct` correctly but are not genuine.

  The ceiling pre-check only reads the claim, so each forgery below passes it; the real engine
  verifies signature, payload digest, signer and expiry and must answer `:lease_refused`. Nothing
  may persist, and the admission is never reported admitted. Every negative is preceded by the
  same lease correctly signed (positive control).

  Attestation-level forgeries (bad signature bytes, payload digest, key id) are built by editing
  the attestation of a real signed lease. Runs only against the real engine (`:wasm`), so it is
  UNKNOWN in a run where the engine is not vendored.
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Error
  alias AshGraphLaw.Test.{Lease, Ticket}

  @moduletag :wasm

  setup do
    start_pool!(size: 2)
    Ash.DataLayer.Ets.stop(Ticket)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Ticket) end)
    :ok
  end

  defp open(signed_lease, title) do
    Ticket
    |> Ash.Changeset.for_create(:open, %{title: title}, context: %{graphlaw_lease: %{signed_lease: signed_lease}})
    |> Ash.create()
  end

  defp flip_hex(<<first, rest::binary>>) do
    replacement = if first == ?0, do: ?1, else: ?0
    <<replacement, rest::binary>>
  end

  defp put_attestation(lease, key, value), do: put_in(lease, ["attestation", key], value)

  test "positive control: the genuine lease is admitted and persisted" do
    assert {:ok, ticket} = open(Lease.signed(:construct), "genuine")
    assert ticket.title == "genuine"
  end

  test "attestation forgeries that keep the :construct claim are refused :lease_refused" do
    genuine = Lease.signed(:construct)
    assert {:ok, _} = open(genuine, "genuine-control")

    forgeries = [
      flipped_signature: put_attestation(genuine, "signature", flip_hex(genuine["attestation"]["signature"])),
      zero_signature: put_attestation(genuine, "signature", String.duplicate("0", 128)),
      truncated_signature: put_attestation(genuine, "signature", binary_part(genuine["attestation"]["signature"], 0, 64)),
      wrong_payload_digest: put_attestation(genuine, "payload_sha256", flip_hex(genuine["attestation"]["payload_sha256"])),
      wrong_key_id: put_attestation(genuine, "key_id", flip_hex(genuine["attestation"]["key_id"])),
      key_id_of_untrusted_signer: put_attestation(genuine, "key_id", Lease.signed(:construct, signer: :untrusted)["attestation"]["key_id"]),
      signature_of_another_lease: put_attestation(genuine, "signature", Lease.signed(:construct, id: "L-other")["attestation"]["signature"])
    ]

    for {kind, lease} <- forgeries do
      title = "forged-#{kind}"
      assert {:error, error} = open(lease, title)
      assert :lease_refused in Error.codes(error), "#{kind}: #{inspect(Error.codes(error))}"
      refute Enum.any?(Ash.read!(Ticket), &(&1.title == title)), "#{kind} was persisted"
    end
  end

  test "body forgeries are refused: holder, id and expiry changed after signing" do
    assert {:ok, _} = open(Lease.signed(:construct), "genuine-control")

    for {kind, tamper} <- [
          holder: %{"holder" => "mallory"},
          id: %{"id" => "L-forged"},
          expiry_extended: %{"expires_unix" => 4_100_000_000},
          scope_widened: %{"scope" => ["admit:shacl", "derive:n3", "derive:hooks", "admit:plan", "derive:everything"]}
        ] do
      title = "forged-#{kind}"
      assert {:error, error} = open(Lease.signed(:construct, tamper: tamper), title)
      assert :lease_refused in Error.codes(error), "#{kind}: #{inspect(Error.codes(error))}"
      refute Enum.any?(Ash.read!(Ticket), &(&1.title == title))
    end
  end

  test "an expired lease and an untrusted signer are refused even when both claims are :construct" do
    assert {:ok, _} = open(Lease.signed(:construct), "genuine-control")

    for {kind, lease} <- [
          expired: Lease.signed(:construct, expires_unix: 1),
          untrusted: Lease.signed(:construct, signer: :untrusted)
        ] do
      assert {:error, error} = open(lease, "forged-#{kind}")
      assert :lease_refused in Error.codes(error)
    end
  end

  test "a refused forgery does not poison the pool: the genuine lease is admitted right after" do
    genuine = Lease.signed(:construct)
    forged = put_attestation(genuine, "signature", String.duplicate("f", 128))

    for _ <- 1..5 do
      assert {:error, error} = open(forged, "forged-repeat")
      assert :lease_refused in Error.codes(error)
    end

    assert {:ok, ticket} = open(genuine, "genuine-after")
    assert ticket.title == "genuine-after"
    refute Enum.any?(Ash.read!(Ticket), &(&1.title == "forged-repeat"))
  end
end
