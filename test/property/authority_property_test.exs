# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Property.AuthorityTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago property suite; real resource, real Ed25519 leases.
  use AshGraphLaw.Test.PropertyCase, async: true

  alias AshGraphLaw.Authority
  alias AshGraphLaw.Test.{Lease, Ticket}

  @rank %{observe: 0, select: 1, construct: 2}
  @forbidden_opts [:signed_lease, :lease, :unverified_lease, :now_unix, :ceiling]

  describe "positive controls" do
    test "a signed lease claims exactly its ceiling and unlocks admissions up to it" do
      for granted <- [:observe, :select, :construct], required <- [:observe, :select, :construct] do
        lease = Lease.container(granted)
        assert %{ceiling: ^granted, signed_lease: %{}} = Authority.claim(lease)

        result = Authority.check_ceiling(admission_requiring(required), lease)

        if @rank[granted] >= @rank[required] do
          assert result == :ok
        else
          assert {:error, %Refusal{code: :ceiling_unmet}} = result
        end
      end
    end
  end

  describe "ceiling monotonicity" do
    property "anything that is not a signed lease claims :observe and no signed lease" do
      check all(lease <- unsigned_lease(), max_runs: max_runs()) do
        assert %{ceiling: :observe, signed_lease: nil} = Authority.claim(lease)
        assert Authority.identity(lease) == nil
      end
    end

    property "a malformed :signed_lease container claims :observe" do
      check all(lease <- malformed_signed_lease(), max_runs: max_runs()) do
        assert %{ceiling: :observe, signed_lease: nil} = Authority.claim(lease)
        assert Authority.identity(lease) == nil
      end
    end

    property "an unsigned shape never satisfies a :select or :construct admission" do
      check all(
              lease <- one_of([unsigned_lease(), malformed_signed_lease()]),
              required <- member_of([:select, :construct]),
              max_runs: max_runs()
            ) do
        assert {:error, %Refusal{code: :ceiling_unmet, class: :refused_authority} = refusal} =
                 Authority.check_ceiling(admission_requiring(required), lease)

        assert refusal.details.granted == :observe
        assert refusal.details.required == required
      end
    end

    property "an :observe admission is satisfied by every shape" do
      check all(
              lease <- one_of([unsigned_lease(), malformed_signed_lease(), map(ceiling(), &Lease.container/1)]),
              max_runs: max_runs()
            ) do
        assert :ok = Authority.check_ceiling(admission_requiring(:observe), lease)
      end
    end

    property "check_ceiling/2 is monotone in the granted ceiling" do
      check all(granted <- ceiling(), required <- ceiling(), max_runs: max_runs()) do
        lease = Lease.container(granted)
        allowed? = Authority.check_ceiling(admission_requiring(required), lease) == :ok
        assert allowed? == @rank[granted] >= @rank[required]

        for higher <- Enum.filter([:observe, :select, :construct], &(@rank[&1] >= @rank[granted])) do
          if allowed?, do: assert(:ok = Authority.check_ceiling(admission_requiring(required), Lease.container(higher)))
        end
      end
    end

    property "no shape ever exceeds :observe without a signed lease, and the claim is bounded by the lease" do
      check all(
              lease <- one_of([unsigned_lease(), malformed_signed_lease(), map(ceiling(), &Lease.container/1)]),
              max_runs: max_runs()
            ) do
        %{ceiling: claimed, signed_lease: signed} = Authority.claim(lease)

        if signed == nil, do: assert(claimed == :observe)
        assert claimed in [:observe, :select, :construct]
      end
    end
  end

  describe "engine_opts/3" do
    property "caller context never supplies trust anchors, a clock or an unsigned lease" do
      check all(lease <- one_of([unsigned_lease(), malformed_signed_lease()]), max_runs: max_runs()) do
        opts = Authority.engine_opts(Ticket, lease, [])

        assert Keyword.keys(opts) -- [:server, :timeout, :max_skew_secs, :trusted_keys] == []
        assert Enum.all?(@forbidden_opts, &(not Keyword.has_key?(opts, &1)))
        assert opts[:trusted_keys] == [Lease.public_key_hex(:trusted)]
      end
    end

    property "a signed lease is forwarded verbatim and trust anchors still come from the resource" do
      check all(granted <- ceiling(), max_runs: max_runs()) do
        container = Lease.container(granted)
        opts = Authority.engine_opts(Ticket, container, [])

        assert opts[:signed_lease] == container.signed_lease
        assert opts[:trusted_keys] == [Lease.public_key_hex(:trusted)]
        refute Keyword.has_key?(opts, :now_unix)
      end
    end
  end

  describe "identity/1" do
    property "is deterministic, names the ceiling, and digests the canonical lease" do
      check all(granted <- ceiling(), id <- word(), max_runs: max_runs()) do
        container = Lease.container(granted, id: id)
        identity = Authority.identity(container)

        assert identity == Authority.identity(container)
        assert identity.ceiling == granted
        assert identity.lease_id == id
        assert identity.lease_digest =~ ~r/\A[0-9a-f]{64}\z/
        assert Authority.identity(Lease.container(granted, id: id <> "x")).lease_digest != identity.lease_digest
      end
    end
  end
end
