# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
defmodule AshGraphLaw.Test.AdmissionOracle do
  @moduledoc """
  UNSUPPORTED(generator-capability): test-only, pure-Elixir admission oracle (C14 differential).
  Re-derives the verdict of the engine `law` op's lease-authorization surface from the DOCUMENTED
  contract (graphlaw `src/law.rs` `Lease::authorize` / `SignedLease::authorize`, `src/abi.rs`
  `lease_auth_of`, `src/attest.rs`; registry `lease_reasons`), and the court in
  `test/integration/admission_differential_test.exs` runs the SAME inputs through the real WASM
  admission path (`AshGraphLaw.Capability.Law.run/2` over the vendored pinned engine) and diffs.
  Oracle contract, in engine evaluation order (a divergence here is a real finding):
  1. request shape, engine parse order (`lease_auth_of`): both `signed_lease` and `lease`
  present -> `{:unsupported, :lease_shape}`; unsigned `lease` without
  `unverified_lease: true` -> `:unverified_lease_refused`; the flag set but `now_unix`
  missing -> `{:unsupported, :lease_shape}`; malformed lease object fields or negative
  `max_skew_secs` -> `{:unsupported, :lease_shape}` (signed path order: attestation parse,
  then lease object, then trusted keys); non-hex `trusted_keys` -> `{:unsupported,
  :trusted_keys}`;
  2. attestation shape (fixed-length hex fields) -> else `{:unsupported, :attestation}`;
  3. `payload_blake3` over the canonical payload mismatch -> `{:lease_refused, "bad_signature"}`;
  4. key_id not among the trusted keys -> `{:lease_refused, "untrusted_key"}`;
  5. Ed25519 signature failure -> `{:lease_refused, "bad_signature"}`;
  6. skew: `issued_unix > now + max_skew_secs` -> `{:lease_refused, "clock_skew"}`;
  7. per step, in order: `now >= expires_unix` -> `{:lease_refused, "expired"}`;
  step name not in scope -> `{:lease_refused, "out_of_scope"}`;
  required ceiling > lease ceiling -> `{:lease_refused, "ceiling"}`;
  8. otherwise `:admitted`.
  Signed leases are judged by the ENGINE's clock; the oracle judges at the corpus base time
  `now0`. Every generated time value is chosen so the verdict is invariant under any engine
  clock `now_e >= now0`: expiry/skew refusals hold or strengthen under time advance, and every
  pass sits on an exact monotone-pass boundary (`issued <= now0 + skew`) or carries a >= 1 hour
  margin. The corpus therefore stays deterministic in verdict space with the real engine clock
  (Chicago: real engine, real clock, real Ed25519; nothing mocked).
  """
  alias AshGraphLaw.Refusal
  @seeds %{trusted: 7, untrusted: 9}
  @far_future 4_000_000_000
  @scope_all ~w(admit:shacl derive:n3 admit:plan admit:require-receipt admit:require-signed-receipt derive:rdfs derive:owl-rl)
  @ceiling_rank %{"observe" => 0, "select" => 1, "construct" => 2}
  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------
  @type verdict ::
          :admitted
          | {:lease_refused, String.t()}
          | :unverified_lease_refused
          | {:unsupported, :attestation | :lease_shape | :trusted_keys}
          | {:other, atom()}
  @type case_t :: %{
          id: String.t(),
          args: map(),
          expected: verdict()
        }
  # ---------------------------------------------------------------------------
  # Corpus
  # ---------------------------------------------------------------------------
  @doc """
  Deterministic differential corpus (>= 200 cases incl. boundaries).
  `now0` is the corpus base time (unix seconds); the court passes `System.system_time(:second)`
  captured immediately before the wave runs. Returns a list of `%{id, args, expected}` maps;
  `args` is a `law` request WITHOUT the `"op"` key (the typed `build_request/1` injects it).
  """
  @spec corpus(pos_integer()) :: [case_t()]
  def corpus(now0) when is_integer(now0) do
    Enum.concat([
      no_lease_cases(),
      signed_grid(now0),
      signed_adversarial(now0),
      signed_multistep(now0),
      unverified_cases(now0)
    ])
  end

  # ---------------------------------------------------------------------------
  # Oracle
  # ---------------------------------------------------------------------------
  @doc "The oracle's re-derived verdict for a corpus case (exported for the sabotage twin)."
  @spec expected(case_t()) :: verdict()
  def expected(%{expected: expected}), do: expected

  @doc """
  Classifies a REAL engine result (`AshGraphLaw.Capability.Law.run/2`) into the oracle's
  verdict space.
  """
  @spec classify({:ok, term()} | {:error, Refusal.t()}) :: verdict()
  def classify({:ok, _admitted}), do: :admitted

  def classify({:error, %Refusal{} = refusal}) do
    details = refusal.details || %{}
    code = details["code"]

    cond do
      code == "LeaseRefused" and is_binary(details["reason"]) ->
        {:lease_refused, details["reason"]}

      code == "UnverifiedLeaseRefused" ->
        :unverified_lease_refused

      refusal.kind == "Unsupported" and String.starts_with?(refusal.message, "`attestation`") ->
        {:unsupported, :attestation}

      refusal.kind == "Unsupported" and String.contains?(refusal.message, "`trusted_keys`") ->
        {:unsupported, :trusted_keys}

      refusal.kind == "Unsupported" ->
        {:unsupported, :lease_shape}

      true ->
        {:other, refusal.code}
    end
  end

  # ---------------------------------------------------------------------------
  # Chains: the four deterministic law chains every case family reuses
  # ---------------------------------------------------------------------------
  # Chain A: one rdfs step. Step name `derive:rdfs`, required ceiling construct (2).
  defp chain_a_args do
    %{
      "data" => %{
        "text" =>
          "<urn:a:C> <http://www.w3.org/2000/01/rdf-schema#subClassOf> <urn:a:D> .\n" <>
            "<urn:a:x> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:a:C> .\n",
        "dialect" => "ntriples"
      },
      "steps" => [%{"step" => "rdfs"}]
    }
  end

  # Chain B: shacl, n3, plan over the registry example data (all three steps admit).
  defp chain_b_args do
    %{
      "data" => %{
        "text" => "@prefix ex: <https://e/> . ex:a a ex:T ; ex:name \"a\" .",
        "dialect" => "turtle"
      },
      "steps" => [
        %{
          "step" => "shacl",
          "shapes" =>
            "@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix ex: <https://e/> .\n" <>
              "ex:S a sh:NodeShape ; sh:targetClass ex:T ; sh:property [ sh:path ex:name ; sh:minCount 1 ] ."
        },
        %{"step" => "n3", "rules" => "@prefix ex: <https://e/> . { ?x a ex:T } => { ?x a ex:Checked } ."},
        %{
          "step" => "plan",
          "plan" => %{
            "actions" => [
              %{
                "name" => "t",
                "pre" => "<https://e/a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://e/Checked> .\n",
                "add" => "<https://e/a> <https://e/done> <https://e/yes> .\n",
                "del" => ""
              }
            ],
            "goal" => "<https://e/a> <https://e/done> <https://e/yes> .\n"
          }
        }
      ]
    }
  end

  # Chain C: one shacl step (required ceiling observe, step name `admit:shacl`).
  defp chain_c_args do
    %{chain_b_args() | "steps" => [hd(chain_b_args()["steps"])]}
  end

  # Chain D: n3 then plan (required ceilings construct, select).
  defp chain_d_args do
    %{"steps" => steps} = chain_b_args()
    %{chain_b_args() | "steps" => Enum.slice(steps, 1, 2)}
  end

  # ---------------------------------------------------------------------------
  # 1. No lease: every chain admits.
  # ---------------------------------------------------------------------------
  defp no_lease_cases do
    [chain_a_args(), chain_b_args(), chain_c_args(), chain_d_args()]
    |> Enum.with_index()
    |> Enum.map(fn {args, i} -> %{id: "none-#{i}", args: args, expected: :admitted} end)
  end

  # ---------------------------------------------------------------------------
  # 2. Signed grid: ceiling x expiry x issuance x skew (trusted signer, full scope).
  # ---------------------------------------------------------------------------
  defp signed_grid(now0) do
    for ceiling <- ["observe", "select", "construct"],
        expires_off <- [-1, 0, 3_600, 86_400, 604_800],
        issued_off <- [-3_600, -1, 0, 30, 59, 60, 90],
        max_skew <- [60, 0],
        # At skew 0 only the exact boundary (issued == now0) and the 90 s-margin refuse
        # keep their verdicts under engine clock advance.
        issued_off not in [30, 59, 60] or max_skew == 60 do
      opts = [
        ceiling: ceiling,
        expires_unix: now0 + expires_off,
        issued_unix: now0 + issued_off,
        max_skew: max_skew
      ]

      %{
        id: "signed-#{ceiling}-e#{expires_off}-i#{issued_off}-s#{max_skew}",
        args: signed_args(sign_lease(opts), max_skew: max_skew),
        expected: signed_grid_verdict(now0, ceiling, now0 + expires_off, now0 + issued_off, max_skew)
      }
    end
  end

  # The oracle proper for the grid: signature trusted + well formed, then skew,
  # then the one rdfs step (name `derive:rdfs`, required ceiling construct) against
  # the lease's expiry and ceiling.
  defp signed_grid_verdict(now0, ceiling, expires, issued, skew) do
    cond do
      issued > now0 + skew -> {:lease_refused, "clock_skew"}
      now0 >= expires -> {:lease_refused, "expired"}
      @ceiling_rank["construct"] > @ceiling_rank[ceiling] -> {:lease_refused, "ceiling"}
      true -> :admitted
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Signed adversarial: signer, attestation, request-shape and priority cases.
  # ---------------------------------------------------------------------------
  defp signed_adversarial(now0) do
    expiry_past = now0 - 1

    [
      # --- signer gating -----------------------------------------------------
      %{
        id: "signed-untrusted-signer",
        args:
          signed_args(sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0),
            signer: :untrusted
          ),
        expected: {:lease_refused, "untrusted_key"}
      },
      %{
        id: "signed-empty-trusted-set",
        args:
          signed_args(sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0),
            trusted: []
          ),
        expected: {:lease_refused, "untrusted_key"}
      },
      # --- attestation order: digest before key lookup ------------------------
      %{
        id: "signed-wrong-payload-digest",
        args: wrong_digest_args(),
        expected: {:lease_refused, "bad_signature"}
      },
      %{
        id: "signed-swapped-key-id",
        args: swapped_key_id_args(),
        # payload digest matches, signature verifies, but the key_id is unknown:
        # the contract reports untrusted_key, not bad_signature.
        expected: {:lease_refused, "untrusted_key"}
      },
      # --- tampered lease body ------------------------------------------------
      %{
        id: "signed-tampered-ceiling",
        args: tampered_args(),
        expected: {:lease_refused, "bad_signature"}
      },
      # --- malformed attestation shapes -> engine Unsupported -----------------
      %{
        id: "signed-sig-nonhex",
        args: malformed_att_args(%{"signature" => "nothex"}),
        expected: {:unsupported, :attestation}
      },
      %{
        id: "signed-sig-short",
        args: malformed_att_args(%{"signature" => String.duplicate("a", 127)}),
        expected: {:unsupported, :attestation}
      },
      %{
        id: "signed-digest-short",
        args: malformed_att_args(%{"payload_blake3" => String.duplicate("a", 63)}),
        expected: {:unsupported, :attestation}
      },
      %{
        id: "signed-keyid-nonhex",
        args: malformed_att_args(%{"key_id" => "xyz"}),
        expected: {:unsupported, :attestation}
      },
      # --- trusted_keys / skew / lease-object shape ---------------------------
      %{id: "signed-trusted-keys-nonhex", args: bad_trusted_keys_args(), expected: {:unsupported, :trusted_keys}},
      %{id: "signed-negative-skew", args: negative_skew_args(), expected: {:unsupported, :lease_shape}},
      %{id: "signed-lease-missing-id", args: missing_field_args(:id), expected: {:unsupported, :lease_shape}},
      %{
        id: "signed-lease-bad-ceiling",
        args: missing_field_args(:ceiling, "root"),
        expected: {:unsupported, :lease_shape}
      },
      %{
        id: "signed-lease-scope-not-list",
        args: missing_field_args(:scope, "derive:rdfs"),
        expected: {:unsupported, :lease_shape}
      },
      %{
        id: "signed-lease-negative-expires",
        args: missing_field_args(:expires_unix, -1),
        expected: {:unsupported, :lease_shape}
      },
      %{
        id: "signed-lease-negative-issued",
        args: missing_field_args(:issued_unix, -1),
        expected: {:unsupported, :lease_shape}
      },
      %{id: "signed-both-lease-keys", args: both_keys_args(), expected: {:unsupported, :lease_shape}},
      # --- priority: first failing check in contract order wins ---------------
      %{
        id: "signed-priority-expiry-before-scope-ceiling",
        args:
          signed_args(
            sign_lease(
              ceiling: "observe",
              expires_unix: expiry_past,
              issued_unix: 0,
              scope: ["admit:shacl"]
            )
          ),
        expected: {:lease_refused, "expired"}
      },
      %{
        id: "signed-priority-skew-before-expiry",
        args:
          signed_args(
            sign_lease(
              ceiling: "construct",
              expires_unix: expiry_past,
              issued_unix: now0 + 90
            ),
            max_skew: 60
          ),
        expected: {:lease_refused, "clock_skew"}
      },
      %{
        id: "signed-priority-ceiling",
        args: signed_args(sign_lease(ceiling: "select", expires_unix: @far_future, issued_unix: 0)),
        expected: {:lease_refused, "ceiling"}
      },
      %{
        id: "signed-priority-out-of-scope",
        args:
          signed_args(
            sign_lease(
              ceiling: "construct",
              expires_unix: @far_future,
              issued_unix: 0,
              scope: ["admit:shacl"]
            )
          ),
        expected: {:lease_refused, "out_of_scope"}
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # 4. Signed multi-step chains: per-step scope/ceiling against a real chain.
  # ---------------------------------------------------------------------------
  defp signed_multistep(now0) do
    [
      %{scope: @scope_all, ceiling: "construct", expires: @far_future},
      %{scope: ~w(admit:shacl derive:n3 admit:plan), ceiling: "select", expires: @far_future},
      %{scope: ~w(admit:shacl), ceiling: "construct", expires: @far_future},
      %{scope: [], ceiling: "construct", expires: @far_future},
      %{scope: @scope_all, ceiling: "observe", expires: @far_future},
      %{scope: @scope_all, ceiling: "construct", expires: 0}
    ]
    |> Enum.with_index()
    |> Enum.map(fn {cfg, i} ->
      lease = sign_lease(ceiling: cfg.ceiling, expires_unix: cfg.expires, issued_unix: 0, scope: cfg.scope)
      expected = multistep_verdict(chain_b_steps(), lease["lease"], now0)

      %{
        id: "signed-multistep-#{i}",
        args: signed_args(lease) |> Map.merge(chain_b_args()),
        expected: expected
      }
    end)
  end

  defp chain_b_steps do
    [
      %{"name" => "admit:shacl", "ceiling" => 0},
      %{"name" => "derive:n3", "ceiling" => 2},
      %{"name" => "admit:plan", "ceiling" => 1}
    ]
  end

  # Per-step authorization in chain order; the first failing step names the reason.
  defp multistep_verdict(steps, lease, now) do
    Enum.find_value(steps, :admitted, fn %{"name" => name, "ceiling" => req} ->
      cond do
        now >= lease["expires_unix"] -> {:lease_refused, "expired"}
        name not in lease["scope"] -> {:lease_refused, "out_of_scope"}
        @ceiling_rank[lease["ceiling"]] < req -> {:lease_refused, "ceiling"}
        true -> nil
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 5. Unverified (unsigned) lease: fully deterministic caller clock.
  # ---------------------------------------------------------------------------
  defp unverified_cases(now0) do
    grid =
      for ceiling <- ["observe", "select", "construct"],
          expires_off <- [-1, 0, 1, 3_600],
          now_off <- [0, 3_600] do
        {ceiling, expires_off, now_off}
      end

    grid_cases =
      Enum.map(grid, fn {ceiling, expires_off, now_off} ->
        now = now0 + now_off
        expires = now0 + expires_off
        lease = lease_body(ceiling: ceiling, expires_unix: expires, issued_unix: 0)
        expected = unverified_verdict(expires, ceiling, now)

        %{
          id: "unverified-#{ceiling}-e#{expires_off}-n#{now_off}",
          args:
            Map.merge(chain_a_args(), %{
              "lease" => lease,
              "unverified_lease" => true,
              "now_unix" => now
            }),
          expected: expected
        }
      end)

    flag_cases = [
      %{
        id: "unverified-flag-absent",
        args: Map.merge(chain_a_args(), %{"lease" => lease_body(ceiling: "construct", expires_unix: @far_future)}),
        expected: :unverified_lease_refused
      },
      %{
        id: "unverified-flag-false",
        args:
          Map.merge(chain_a_args(), %{
            "lease" => lease_body(ceiling: "construct", expires_unix: @far_future),
            "unverified_lease" => false
          }),
        expected: :unverified_lease_refused
      },
      %{
        id: "unverified-missing-now-unix",
        args:
          Map.merge(chain_a_args(), %{
            "lease" => lease_body(ceiling: "construct", expires_unix: @far_future),
            "unverified_lease" => true
          }),
        expected: {:unsupported, :lease_shape}
      },
      %{
        id: "unverified-out-of-scope",
        args:
          Map.merge(chain_a_args(), %{
            "lease" => lease_body(ceiling: "construct", expires_unix: @far_future, scope: ["admit:shacl"]),
            "unverified_lease" => true,
            "now_unix" => now0
          }),
        expected: {:lease_refused, "out_of_scope"}
      },
      %{
        id: "unverified-ceiling-select",
        args:
          Map.merge(chain_a_args(), %{
            "lease" => lease_body(ceiling: "select", expires_unix: @far_future),
            "unverified_lease" => true,
            "now_unix" => now0
          }),
        expected: {:lease_refused, "ceiling"}
      }
    ]

    grid_cases ++ flag_cases
  end

  # The oracle proper for the unverified path: the caller's own clock, the one
  # rdfs step (name `derive:rdfs`, required ceiling construct) against the lease.
  defp unverified_verdict(expires, ceiling, now) do
    cond do
      now >= expires -> {:lease_refused, "expired"}
      @ceiling_rank["construct"] > @ceiling_rank[ceiling] -> {:lease_refused, "ceiling"}
      true -> :admitted
    end
  end

  # ---------------------------------------------------------------------------
  # Request assembly
  # ---------------------------------------------------------------------------
  defp signed_args(signed, extra \\ []) do
    trusted = Keyword.get(extra, :trusted, trusted_keys())
    max_skew = Keyword.get(extra, :max_skew, 60)
    signer = Keyword.get(extra, :signer, :trusted)

    signed =
      if signer == :untrusted do
        {pub, priv} = keypair(:untrusted)
        body = Map.get(signed, "lease")
        payload = canonical_payload(body)

        %{
          "lease" => body,
          "attestation" => %{
            "key_id" => blake3_hex(pub),
            "payload_blake3" => blake3_hex(payload),
            "signature" => hex_sign(payload, priv)
          }
        }
      else
        signed
      end

    chain_a_args()
    |> Map.merge(%{
      "signed_lease" => signed,
      "trusted_keys" => trusted,
      "max_skew_secs" => max_skew
    })
  end

  defp wrong_digest_args do
    signed = sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0)

    attestation =
      signed["attestation"]
      |> Map.put("payload_blake3", blake3_hex("not the payload"))

    Map.merge(chain_a_args(), %{"signed_lease" => %{"lease" => signed["lease"], "attestation" => attestation}})
    |> Map.merge(%{"trusted_keys" => trusted_keys(), "max_skew_secs" => 60})
  end

  defp swapped_key_id_args do
    {untrusted_pub, _} = keypair(:untrusted)
    signed = sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0)
    attestation = Map.put(signed["attestation"], "key_id", blake3_hex(untrusted_pub))

    Map.merge(chain_a_args(), %{"signed_lease" => %{"lease" => signed["lease"], "attestation" => attestation}})
    |> Map.merge(%{"trusted_keys" => trusted_keys(), "max_skew_secs" => 60})
  end

  defp tampered_args do
    signed = sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0)
    body = Map.put(signed["lease"], "ceiling", "observe")

    Map.merge(chain_a_args(), %{"signed_lease" => %{"lease" => body, "attestation" => signed["attestation"]}})
    |> Map.merge(%{"trusted_keys" => trusted_keys(), "max_skew_secs" => 60})
  end

  defp malformed_att_args(override) do
    signed = sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0)
    attestation = Map.merge(signed["attestation"], override)

    Map.merge(chain_a_args(), %{"signed_lease" => %{"lease" => signed["lease"], "attestation" => attestation}})
    |> Map.merge(%{"trusted_keys" => trusted_keys(), "max_skew_secs" => 60})
  end

  defp bad_trusted_keys_args do
    signed = sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0)

    chain_a_args()
    |> Map.merge(%{"signed_lease" => signed, "trusted_keys" => ["not-hex"], "max_skew_secs" => 60})
  end

  defp negative_skew_args do
    signed = sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0)

    chain_a_args()
    |> Map.merge(%{"signed_lease" => signed, "trusted_keys" => trusted_keys(), "max_skew_secs" => -1})
  end

  # Builds a signed lease whose body omits or overrides one field.
  defp missing_field_args(field, override \\ nil) do
    body =
      %{
        "id" => "L-missing",
        "holder" => "test",
        "ceiling" => "construct",
        "scope" => @scope_all,
        "expires_unix" => @far_future,
        "issued_unix" => 0
      }
      |> Map.delete(Atom.to_string(field))
      |> then(fn body ->
        if override == nil, do: body, else: Map.put(body, Atom.to_string(field), override)
      end)

    # Sign whatever the body says, so only the named field is malformed.
    signed = sign_body(body)

    chain_a_args()
    |> Map.merge(%{"signed_lease" => signed, "trusted_keys" => trusted_keys(), "max_skew_secs" => 60})
  end

  defp both_keys_args do
    signed = sign_lease(ceiling: "construct", expires_unix: @far_future, issued_unix: 0)

    chain_a_args()
    |> Map.merge(%{
      "signed_lease" => signed,
      "lease" => lease_body(ceiling: "construct", expires_unix: @far_future),
      "trusted_keys" => trusted_keys(),
      "max_skew_secs" => 60
    })
  end

  # ---------------------------------------------------------------------------
  # Lease building and real Ed25519 signing (same mechanics as Test.Lease)
  # ---------------------------------------------------------------------------
  defp sign_lease(opts) do
    body = lease_body(opts)
    sign_body(body)
  end

  defp lease_body(opts) do
    %{
      "id" => Keyword.get(opts, :id, "L-#{:erlang.phash2(opts)}"),
      "holder" => "test",
      "ceiling" => Keyword.fetch!(opts, :ceiling),
      "scope" => Keyword.get(opts, :scope, @scope_all),
      "expires_unix" => Keyword.fetch!(opts, :expires_unix),
      "issued_unix" => Keyword.get(opts, :issued_unix, 0)
    }
  end

  defp sign_body(body) do
    {pub, priv} = keypair(:trusted)
    payload = canonical_payload(body)

    %{
      "lease" => body,
      "attestation" => %{
        "key_id" => blake3_hex(pub),
        "payload_blake3" => blake3_hex(payload),
        "signature" => hex_sign(payload, priv)
      }
    }
  end

  # Sorted-key, no-whitespace canonical payload (graphlaw attest.rs `lease_payload`):
  # ceiling, expires_unix, holder, id, issued_unix, scope (order preserved).
  defp canonical_payload(body) do
    # Malformed bodies (scope a bare string, a missing field) are refused by the engine at
    # lease-object parse time, before any digest is recomputed; the signature payload for
    # those cases only needs to be constructible, never verifiable.
    scope_json =
      case body["scope"] do
        scope when is_list(scope) -> scope |> Enum.map(&Jason.encode!/1) |> Enum.join(",")
        other -> Jason.encode!(other)
      end

    ~s({"ceiling":#{Jason.encode!(body["ceiling"])},"expires_unix":#{body["expires_unix"]},) <>
      ~s("holder":#{Jason.encode!(body["holder"])},"id":#{Jason.encode!(body["id"])},) <>
      ~s("issued_unix":#{body["issued_unix"]},"scope":[#{scope_json}]})
  end

  defp trusted_keys do
    [AshGraphLaw.Test.Lease.public_key_hex(:trusted)]
  end

  defp keypair(signer) do
    seed = Map.fetch!(@seeds, signer)
    :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<seed>>, 32))
  end

  defp hex_sign(payload, priv) do
    :eddsa |> :crypto.sign(:none, payload, [priv, :ed25519]) |> Base.encode16(case: :lower)
  end

  defp blake3_hex(bytes) do
    path = Path.join(System.tmp_dir!(), "ash-graphlaw-oracle-#{System.unique_integer([:positive])}")

    try do
      File.write!(path, bytes)

      case System.cmd("b3sum", [path], stderr_to_stdout: true) do
        {out, 0} -> out |> String.split() |> List.first()
        {out, code} -> raise "b3sum failed (exit #{code}): #{String.trim(out)}"
      end
    after
      File.rm(path)
    end
  end
end
