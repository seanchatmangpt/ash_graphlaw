# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.AdmissionDifferentialTest do
  @moduledoc """
  The C14 admission differential court: the pure-Elixir oracle
  (`AshGraphLaw.Test.AdmissionOracle`) re-derives the lease-authorization verdict from the
  documented contract; the SAME inputs run through the REAL WASM admission path
  (`AshGraphLaw.Capability.Law.run/2` over the vendored pinned engine) and the two are diffed.

  Pass = zero divergences. Any divergence is a typed failure naming the case id, the inputs and
  both verdicts. The sabotage twin flips one oracle verdict and must produce exactly one
  divergence: a court that cannot fail is not a court.

  UNSUPPORTED(generator-capability): hand-written Chicago court; real engine, real Ed25519,
  no mocks.
  """

  use AshGraphLaw.Test.Case

  alias AshGraphLaw.Capability.Law
  alias AshGraphLaw.Test.AdmissionOracle

  @moduletag :wasm

  @min_corpus_size 200

  describe "the corpus" do
    test "is deterministic and at least #{@min_corpus_size} cases" do
      now0 = System.system_time(:second)
      cases = AdmissionOracle.corpus(now0)

      assert length(cases) >= @min_corpus_size
      assert Enum.uniq_by(cases, & &1.id) == cases

      # Determinism: rebuilding at the SAME base time yields the same ids and expectations.
      assert AdmissionOracle.corpus(now0) == cases
    end

    test "covers the boundary surfaces named by the contract" do
      cases = AdmissionOracle.corpus(System.system_time(:second))
      ids = Enum.map(cases, & &1.id)

      for {prefix, what} <- [
            {"signed-construct-e0-", "expiry edge: expires == now0"},
            {"signed-construct-e3600-i60-s60", "skew edge: issued == now0 + skew (pass)"},
            {"signed-construct-e3600-i90-s60", "skew edge: issued beyond skew (refuse)"},
            {"signed-untrusted-signer", "untrusted key"},
            {"signed-tampered-ceiling", "bad signature"},
            {"unverified-construct-e0-", "unverified expiry edge at caller clock"},
            {"none-", "no lease"}
          ] do
        assert Enum.any?(ids, &String.starts_with?(&1, prefix)),
               "corpus lacks a case for #{what} (prefix #{inspect(prefix)})"
      end
    end
  end

  describe "the differential" do
    test "the oracle and the REAL engine agree on every case" do
      require_engine!()
      now0 = System.system_time(:second)
      cases = AdmissionOracle.corpus(now0)
      host = start_host!()

      divergences = run_wave(cases, host)

      if divergences != [] do
        first = Enum.take(divergences, 5)

        flunk("""
        #{length(divergences)} oracle/engine divergence(s); first 5:

        #{Enum.map_join(first, "\n\n", &format_divergence/1)}
        """)
      end
    end

    test "sabotage twin: flipping one oracle verdict fails the court with exactly one divergence" do
      require_engine!()
      now0 = System.system_time(:second)
      cases = AdmissionOracle.corpus(now0)
      host = start_host!()

      # Flip the verdict of one case whose engine answer is stable (a no-lease admit).
      target_id = "none-0"

      sabotaged =
        Enum.map(cases, fn
          %{id: ^target_id} = c -> %{c | expected: {:lease_refused, "expired"}}
          other -> other
        end)

      divergences = run_wave(sabotaged, host)

      assert [%{id: ^target_id}] = divergences
      assert %{id: ^target_id} = hd(divergences)
    end
  end

  # One wave: every case through the real engine, classified, diffed against the oracle.
  defp run_wave(cases, host) do
    for %{id: id, args: args, expected: expected} <- cases,
        result = Law.run(args, server: host),
        actual = AdmissionOracle.classify(result),
        actual != expected do
      %{id: id, args: args, oracle: expected, engine: actual}
    end
  end

  defp format_divergence(%{id: id, args: args, oracle: oracle, engine: engine}) do
    """
    case #{id}
      inputs:   #{inspect(args, limit: 12)}
      oracle:   #{inspect(oracle)}
      engine:   #{inspect(engine)}
    """
  end
end
