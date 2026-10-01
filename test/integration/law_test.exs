# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.LawTest do
  @moduledoc """
  Real-wasm `law` pipeline tests. Request and refusal shapes are taken from
  graphlaw `tests/wasm_abi.rs`, `plan_admission.rs`, `receipt_lease.rs` and
  `docs/refusals.md`. Admission is an observation, never authority.
  UNSUPPORTED(generator-capability): hand-written.
  """
  use AshGraphLaw.Test.Case

  alias AshGraphLaw.{Admitted, Receipt, Refusal, Standing}

  @moduletag :wasm

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> . @prefix ex: <https://e/> .
  ex:S a sh:NodeShape ; sh:targetClass ex:T ;
    sh:property [ sh:path ex:name ; sh:minCount 1 ] .
  """

  @good "<https://e/a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/T> .\n<https://e/a> <https://e/name> \"a\" .\n"
  @two_bad "<https://e/a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/T> .\n<https://e/b> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/T> .\n"

  @rdfs_data "<urn:a:C> <http://www.w3.org/2000/01/rdf-schema#subClassOf> <urn:a:D> .\n<urn:a:x> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:a:C> .\n"

  setup do
    %{server: start_host!([])}
  end

  defp data_spec(text), do: %{"text" => text, "dialect" => "ntriples"}
  defp shacl_step, do: %{"step" => "shacl", "shapes" => @shapes}

  defp at(o), do: "<urn:p:robot> <urn:p:at> <urn:p:#{o}> .\n"

  defp plan_steps(mid_pre) do
    [
      %{
        "step" => "plan",
        "plan" => %{
          "actions" => [
            %{"name" => "a-b", "pre" => at("a"), "add" => at("b"), "del" => at("a")},
            %{"name" => "b-c", "pre" => at(mid_pre), "add" => at("c"), "del" => at("b")}
          ],
          "goal" => at("c")
        }
      }
    ]
  end

  defp detail(%Refusal{details: d}, key) when is_map(d) do
    case d do
      %{^key => v} -> v
      _ -> Map.get(d, String.to_atom(key))
    end
  end

  defp nested_detail(%Refusal{details: d} = r, key) when is_map(d) do
    detail(r, key) || get_in(d, ["details", key]) || get_in(d, [:details, key])
  end

  test "SHACL conformant data is admitted with a receipt (PARTIAL_ALIVE, never ALIVE)", %{server: s} do
    result = AshGraphLaw.law(data_spec(@good), [shacl_step()], server: s)
    assert {:ok, %Admitted{states: states, receipts: [%Receipt{} = receipt]}} = result
    # an admission gate does not change the state
    assert [same, same] = states
    assert receipt.authority == "purrdf::shapes"
    assert Standing.of(result) == :PARTIAL_ALIVE
    refute Standing.of(result) == :ALIVE
  end

  test "SHACL violating data is refused by the engine as :not_admitted (standing UNKNOWN)", %{server: s} do
    # positive control: conformant data passes the same shapes
    assert {:ok, %Admitted{}} = AshGraphLaw.law(data_spec(@good), [shacl_step()], server: s)

    data = %{"text" => @two_bad, "dialect" => "turtle"}

    # The engine reports a SHACL violation as `NotAdmitted`, projected :not_admitted / :refused_admission.
    assert {:error, %Refusal{code: :not_admitted, class: :refused_admission, kind: "EngineRejected"} = r} =
             AshGraphLaw.law(data, [shacl_step()], server: s)

    assert Standing.of({:error, r}) == :UNKNOWN
  end

  test "a feasible plan step is admitted and records a plan-action receipt", %{server: s} do
    # positive control: the same data is admitted by a step the engine already implemented
    assert {:ok, %Admitted{}} = AshGraphLaw.law(data_spec(at("a")), [%{"step" => "rdfs"}], server: s)

    assert {:ok, %Admitted{receipts: receipts}} =
             AshGraphLaw.law(data_spec(at("a")), plan_steps("b"), server: s)

    assert Enum.any?(receipts, &(&1.step == "plan-action"))
  end

  test "an unmet-precondition plan is refused as :plan_refused", %{server: s} do
    # positive control: the feasible variant of the same plan is admitted
    assert {:ok, %Admitted{}} = AshGraphLaw.law(data_spec(at("a")), plan_steps("b"), server: s)

    assert {:error, %Refusal{code: :plan_refused} = r} =
             AshGraphLaw.law(data_spec(at("a")), plan_steps("z"), server: s)

    assert Standing.of({:error, r}) == :UNKNOWN
  end

  test "require-receipt without a recorded receipt is refused as :receipt_required", %{server: s} do
    # positive control: the same data passes a plain rdfs step
    assert {:ok, %Admitted{}} = AshGraphLaw.law(data_spec(at("a")), [%{"step" => "rdfs"}], server: s)

    steps = [%{"step" => "require-receipt", "step_name" => "derive:rdfs"}]

    assert {:error, %Refusal{code: :receipt_required} = r} =
             AshGraphLaw.law(data_spec(at("a")), steps, server: s)

    assert Standing.of({:error, r}) == :UNKNOWN
  end

  @tag skip:
         "UNSUPPORTED(engine-capability): graphlaw v26.9.28 ignores lease keys (no expiry, signature or signer verification, no lease_id on receipts)"
  test "a valid unverified lease admits and the receipt carries the lease id", %{server: s} do
    lease = %{
      "id" => "L1",
      "holder" => "h",
      "ceiling" => "construct",
      "scope" => ["derive:rdfs"],
      "expires_unix" => 100
    }

    assert {:ok, %Admitted{receipts: [%Receipt{lease_id: "L1"}]}} =
             AshGraphLaw.law(data_spec(@rdfs_data), [%{"step" => "rdfs"}],
               server: s,
               lease: lease,
               unverified_lease: true,
               now_unix: 50
             )
  end

  @tag skip:
         "UNSUPPORTED(engine-capability): graphlaw v26.9.28 ignores lease keys (no expiry, signature or signer verification, no lease_id on receipts)"
  test "an expired lease is refused :lease_refused with reason expired", %{server: s} do
    lease = %{
      "id" => "L1",
      "holder" => "h",
      "ceiling" => "construct",
      "scope" => ["derive:rdfs"],
      "expires_unix" => 100
    }

    opts = [server: s, lease: lease, unverified_lease: true]

    # positive control: one second before expiry
    assert {:ok, %Admitted{}} = AshGraphLaw.law(data_spec(@rdfs_data), [%{"step" => "rdfs"}], [now_unix: 99] ++ opts)

    assert {:error, %Refusal{code: :lease_refused, class: :refused_authority} = r} =
             AshGraphLaw.law(data_spec(@rdfs_data), [%{"step" => "rdfs"}], [now_unix: 100] ++ opts)

    assert nested_detail(r, "reason") == "expired"
    assert r.broken_term == :R_missing_authority
  end

  @tag skip:
         "UNSUPPORTED(engine-capability): graphlaw v26.9.28 ignores lease keys (no expiry, signature or signer verification, no lease_id on receipts)"
  test "an unsigned lease without :unverified_lease is refused (typed, not admitted)", %{server: s} do
    lease = %{
      "id" => "L1",
      "holder" => "h",
      "ceiling" => "construct",
      "scope" => ["derive:rdfs"],
      "expires_unix" => 100
    }

    base = [server: s, lease: lease, now_unix: 50]

    # positive control: explicitly unverified is admitted
    assert {:ok, %Admitted{}} =
             AshGraphLaw.law(data_spec(@rdfs_data), [%{"step" => "rdfs"}], [unverified_lease: true] ++ base)

    assert {:error, %Refusal{} = r} = AshGraphLaw.law(data_spec(@rdfs_data), [%{"step" => "rdfs"}], base)
    IO.puts("[law_test] unsigned lease observed: code=#{inspect(r.code)} details=#{inspect(r.details)}")
    assert r.code in [:lease_refused, :engine_refused, :engine_unclassified]
    assert r.class in [:refused_authority, :refused_structure, :unsupported]
  end

  describe "signed lease (real Ed25519 via :crypto)" do
    # graphlaw attest.rs: payload = canonical sorted-key JSON of the lease; payload_sha256 = sha256(payload);
    # key_id = sha256(raw public key); signature = Ed25519 over the payload bytes.
    defp keypair(seed_byte) do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<seed_byte>>, 32))
      {pub, priv}
    end

    defp hex(bin), do: Base.encode16(bin, case: :lower)

    defp signed_lease({pub, priv}, expires, tamper_expires \\ nil) do
      payload =
        ~s({"ceiling":"construct","expires_unix":#{expires},"holder":"h","id":"L1","issued_unix":0,"scope":["derive:rdfs"]})

      sig = :crypto.sign(:eddsa, :none, payload, [priv, :ed25519])

      %{
        "lease" => %{
          "id" => "L1",
          "holder" => "h",
          "ceiling" => "construct",
          "scope" => ["derive:rdfs"],
          "expires_unix" => tamper_expires || expires,
          "issued_unix" => 0
        },
        "attestation" => %{
          "key_id" => hex(:crypto.hash(:sha256, pub)),
          "payload_sha256" => hex(:crypto.hash(:sha256, payload)),
          "signature" => hex(sig)
        }
      }
    end

    defp run(server, signed, {pub, _}) do
      AshGraphLaw.law(data_spec(@rdfs_data), [%{"step" => "rdfs"}],
        server: server,
        signed_lease: signed,
        trusted_keys: [hex(pub)],
        now_unix: 0
      )
    end

    test "positive control: a correctly signed lease request is admitted (the pinned engine does not verify it)", %{
      server: s
    } do
      k = keypair(3)
      # Admission is observed; lease verification is UNSUPPORTED(engine-capability) in v26.9.28.
      assert {:ok, %Admitted{receipts: [%Receipt{}]}} = run(s, signed_lease(k, 4_000_000_000), k)
    end

    @tag skip:
           "UNSUPPORTED(engine-capability): graphlaw v26.9.28 ignores lease keys (no expiry, signature or signer verification, no lease_id on receipts)"
    test "trusted, unexpired, untampered signed lease is admitted", %{server: s} do
      k = keypair(3)
      assert {:ok, %Admitted{receipts: [%Receipt{lease_id: "L1"}]}} = run(s, signed_lease(k, 4_000_000_000), k)
    end

    @tag skip:
           "UNSUPPORTED(engine-capability): graphlaw v26.9.28 ignores lease keys (no expiry, signature or signer verification, no lease_id on receipts)"
    test "expired (module clock), untrusted signer and tampered lease are each refused", %{server: s} do
      k = keypair(3)
      # positive control
      assert {:ok, %Admitted{}} = run(s, signed_lease(k, 4_000_000_000), k)

      assert {:error, %Refusal{code: :lease_refused} = expired} = run(s, signed_lease(k, 100), k)
      assert nested_detail(expired, "reason") == "expired"

      assert {:error, %Refusal{code: :lease_refused} = untrusted} = run(s, signed_lease(keypair(4), 4_000_000_000), k)
      assert nested_detail(untrusted, "reason") == "untrusted_key"

      assert {:error, %Refusal{code: :lease_refused} = tampered} = run(s, signed_lease(k, 100, 4_000_000_000), k)
      assert nested_detail(tampered, "reason") == "bad_signature"
    end
  end
end
