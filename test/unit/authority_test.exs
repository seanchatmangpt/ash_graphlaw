# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.AuthorityTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago test; real resource, real Ed25519 leases.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Authority
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.Test.{Lease, Ticket}

  defp admission(name) do
    {:ok, admission} = Admissions.fetch(Ticket, name)
    admission
  end

  describe "claim/1" do
    test "positive control: a signed lease claims exactly its ceiling" do
      for ceiling <- [:observe, :select, :construct] do
        assert %{ceiling: ^ceiling, signed_lease: %{"lease" => _}} = Authority.claim(Lease.container(ceiling))
      end
    end

    test "everything that is not a signed lease claims :observe" do
      for lease <- [
            nil,
            :construct,
            "construct",
            42,
            %{},
            [],
            %{ceiling: :construct},
            [ceiling: :construct],
            %{lease: %{"ceiling" => "construct"}},
            %{signed_lease: nil},
            %{signed_lease: %{}},
            %{signed_lease: %{"lease" => %{"ceiling" => "root"}}},
            %{signed_lease: %{"lease" => "construct"}}
          ] do
        assert %{ceiling: :observe, signed_lease: nil} = Authority.claim(lease), inspect(lease)
      end
    end

    test "atom-keyed signed leases are read like string-keyed ones" do
      atomized = %{lease: %{ceiling: :select, id: "A"}, attestation: %{key_id: "k"}}
      assert %{ceiling: :select} = Authority.claim(%{signed_lease: atomized})
    end
  end

  describe "check_ceiling/2" do
    test "an :observe admission needs no lease; a :construct admission needs a signed :construct lease" do
      observe = %{admission(:ticket_shape) | ceiling: :observe}
      assert :ok = Authority.check_ceiling(observe, nil)

      shape = admission(:ticket_shape)
      assert shape.ceiling == :construct
      assert :ok = Authority.check_ceiling(shape, Lease.container(:construct))

      for lease <- [nil, :construct, %{ceiling: :construct}, Lease.container(:select), Lease.container(:observe)] do
        assert {:error, %Refusal{code: :ceiling_unmet, class: :refused_authority} = refusal} =
                 Authority.check_ceiling(shape, lease)

        assert refusal.details.required == :construct
      end
    end

    test "an :select admission accepts a signed :select or :construct lease and refuses :observe" do
      close = admission(:ticket_close)
      assert close.ceiling == :select

      assert :ok = Authority.check_ceiling(close, Lease.container(:select))
      assert :ok = Authority.check_ceiling(close, Lease.container(:construct))
      assert {:error, %Refusal{code: :ceiling_unmet}} = Authority.check_ceiling(close, Lease.container(:observe))
    end
  end

  describe "engine_opts/3" do
    test "trust anchors and skew come from the resource runtime only; the clock is never forwarded" do
      trusted = Lease.public_key_hex(:trusted)
      attacker = Lease.public_key_hex(:untrusted)

      hostile = %{
        signed_lease: Lease.signed(:construct, signer: :untrusted),
        trusted_keys: [attacker],
        max_skew_secs: 1_000_000_000,
        now_unix: 0,
        unverified_lease: true,
        lease: %{"ceiling" => "construct"}
      }

      opts = Authority.engine_opts(Ticket, hostile, timeout: 250)

      assert opts[:trusted_keys] == [trusted]
      assert opts[:max_skew_secs] == 60
      assert opts[:timeout] == 250
      assert opts[:server] == AshGraphLaw.Pool
      assert %{"lease" => _} = opts[:signed_lease]

      for forbidden <- [:now_unix, :unverified_lease, :lease], do: refute(Keyword.has_key?(opts, forbidden))
      assert Enum.count(opts, &(elem(&1, 0) == :trusted_keys)) == 1
    end

    test "without a signed lease no lease material is sent at all" do
      for lease <- [nil, :construct, %{ceiling: :construct}, %{lease: %{}, unverified_lease: true}] do
        opts = Authority.engine_opts(Ticket, lease, [])
        refute Keyword.has_key?(opts, :signed_lease)
        refute Keyword.has_key?(opts, :lease)
        assert opts[:timeout] == 5000
      end
    end

    test "a nil :server or :timeout option falls back to the pool and the runtime timeout" do
      opts = Authority.engine_opts(Ticket, nil, server: nil, timeout: nil)
      assert opts[:server] == AshGraphLaw.Pool
      assert opts[:timeout] == 5000
    end
  end

  describe "identity/1" do
    test "positive control: a signed lease is named by ceiling, lease id, signer key id and digest" do
      signed = Lease.signed(:select, id: "L-42")
      identity = Authority.identity(%{signed_lease: signed})

      assert %{ceiling: :select, lease_id: "L-42", key_id: key_id, lease_digest: digest} = identity
      assert key_id == signed["attestation"]["key_id"]
      assert digest =~ ~r/\A[0-9a-f]{64}\z/
      assert Authority.identity(%{signed_lease: signed}) == identity
    end

    test "the digest binds the whole signed lease: a different signature is a different identity" do
      a = Authority.identity(%{signed_lease: Lease.signed(:select, id: "L-1")})
      b = Authority.identity(%{signed_lease: Lease.signed(:select, id: "L-1", tamper: %{"holder" => "x"})})
      assert a.lease_digest != b.lease_digest
    end

    test "no signed lease, no identity" do
      for lease <- [nil, :construct, %{ceiling: :construct}, %{}] do
        assert Authority.identity(lease) == nil
      end
    end
  end
end
