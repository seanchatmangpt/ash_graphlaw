<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Declare an Admission

Add a `graphlaw` section to a resource and attach one admission to an action.

## 1. Add the extension

```elixir
use Ash.Resource,
  domain: MyApp.Domain,
  extensions: [AshGraphLaw.Resource]
```

## 2. Declare `runtime` and `admission`

```elixir
graphlaw do
  runtime do
    timeout_ms 5000
    max_skew_secs 60
  end

  admission :ticket_close do
    step :plan
    ceiling :select
    law MyApp.TicketPlanLaw
  end
end
```

`runtime` fields: `wasm_path` (default `nil`), `timeout_ms` (5000), `max_skew_secs` (60),
`trusted_keys` (`[]`, 64-character hex strings).

`admission` fields: `name` (required), `step` (required, one of `:shacl`, `:n3`, `:rdfs`,
`:owl_rl`, `:hooks`, `:plan`, `:require_receipt`, `:require_signed_receipt`), `ceiling`
(`:observe`, `:select`, `:construct`; default `:construct`), `law`, `projection`.

## 3. Attach it

```elixir
update :close do
  change {AshGraphLaw.Change.Admit, admission: :ticket_close}
end
```

`AshGraphLaw.Validation.Admissible` (pass or fail only, no evidence) and
`AshGraphLaw.Preparation.Admit` (queries and action inputs) take the same `:admission` option.

## 4. Pass a signed lease that meets the ceiling

Order is `:observe < :select < :construct`. `:observe` needs no lease. Otherwise put a **signed**
lease in the changeset context under `:graphlaw_lease`, as a map with a `:signed_lease` entry:

```elixir
signed = %{
  "lease" => %{"id" => "L1", "holder" => "svc", "ceiling" => "select",
               "scope" => ["admit:plan"], "expires_unix" => 4_000_000_000, "issued_unix" => 0},
  "attestation" => %{"key_id" => key_id, "payload_sha256" => digest, "signature" => signature}
}

Ash.Changeset.for_update(ticket, :close, %{}, context: %{graphlaw_lease: %{signed_lease: signed}})
```

A bare ceiling atom (`:select`), `%{ceiling: :select}` or an unsigned `:lease` grants only
`:observe`: a caller cannot self-grant by writing into context. An unmet ceiling refuses with
`:ceiling_unmet` before the engine is called. The signer must be listed in the resource's
`runtime` `trusted_keys`; the engine verifies signature, signer and expiry itself and refuses
`:lease_refused` otherwise. Trust anchors, skew and the clock never come from caller context.
See [Authority Boundary](../topics/authority_boundary.md).

## 5. Rules checked at compile time

`AshGraphLaw.Contract.validate/1` refuses duplicate admission names, steps that need a payload
without a `law` module (all except `:rdfs` and `:owl_rl`), a declared `law` module that does not
exist or does not export `steps/2`, malformed `trusted_keys`, and `timeout_ms <= 0` or
`max_skew_secs < 0`. A compiled state that is not a map with a `:graphlaw` list is refused rather
than treated as empty.

## See Also

- [Write a Law Module](write_a_law_module.md)
- [Handle Refusals](handle_refusals.md)
- [DSL Reference](../reference/dsl_reference.md)
- [First Admitted Action](../tutorials/first_admitted_action.md)
