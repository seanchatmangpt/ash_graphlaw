<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Mint and Verify a Signed Lease

A lease raises authority above `:observe`. AshGraphLaw never issues or signs leases; it forwards a
lease you present and the engine verifies signature, signer and expiry.

## What a lease is

```text
%{signed_lease: %{"lease" => %{...}, "attestation" => %{...}}}
```

`lease` holds `id`, `holder`, `ceiling` (`observe`, `select` or `construct`), `scope`,
`issued_unix` and `expires_unix`. `attestation` holds `key_id` (sha256 of the raw Ed25519 public
key), `payload_sha256` and `signature` (hex). The signed payload is the sorted-key compact JSON of
the lease body.

## Mint (key custody is yours)

`test/support/lease.ex` (`AshGraphLaw.Test.Lease`) is a real signer used by the test suite: it signs
with `:crypto` Ed25519 over the canonical payload. Copy its approach for your own issuer; do not
use its fixed test seeds outside tests.

## Trust the signer

List the hex public key in the resource `runtime` section. These are the only trust anchors:

```elixir
graphlaw do
  runtime do
    trusted_keys ["<64 hex characters>"]
    max_skew_secs 60
  end
end
```

## Present the lease

A change reads the lease from `changeset.context[:graphlaw_lease]`:

```elixir
Ash.Changeset.for_create(MyApp.Ticket, :open, %{title: "x"},
  context: %{graphlaw_lease: %{signed_lease: signed}}
)
```

`AshGraphLaw.Authority.claim/1` accepts only the `%{signed_lease: ...}` container. A bare atom,
`%{ceiling: :construct}` or an unsigned `lease` claims `:observe`.

## Verify

Two checks run, in order:

1. Presentation check, before the engine: the claimed ceiling must meet the admission `ceiling`,
   else `:ceiling_unmet`.
2. Engine check: signature, trusted signer, expiry, scope and skew. Failure is `:lease_refused`,
   with `details["reason"]` one of `expired`, `out_of_scope`, `ceiling`, `bad_signature`,
   `untrusted_key`, `clock_skew`.

Evidence records the lease identity (ceiling, lease id, signer key id, lease digest); see
[replay admission evidence](replay_admission_evidence.md).

## See Also

- [Authority boundary](../topics/authority_boundary.md)
- [Security model](../topics/security_model.md)
- [Usage rule: authority](../../usage-rules/authority.md)
