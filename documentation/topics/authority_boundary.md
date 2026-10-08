<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# authority_boundary

GraphLaw derives and validates. It never authorizes. This library inherits that rule and adds
no authority of its own.

## Three separate things

| Thing | What it is | Who produces it |
|---|---|---|
| Observation | The engine ran a step on an exact input and returned a result | `graphlaw.wasm` |
| Evidence | An `AshGraphLaw.Evidence` binding that observation to an input digest | this library |
| Authority | Permission to cause a consequence | outside this library |

An admitted action means: on this projected input (identified by sha256), these steps were
observed to pass. It does not mean the action was permitted, and it does not mean any
consequence was executed.

## Evidence is an observation

`AshGraphLaw.Evidence` carries the admission name, the derived standing, the input digest, the
graph ids, the receipts, the engine's wasm sha256 and GraphLaw release, and its own digest
(sha256 of the canonical sorted-key JSON). Two properties follow:

- It is bound to a subject: change the projected text and the digest changes.
- It is bound to an engine identity: a different wasm digest is a different observation.

Receipts returned by the engine prove presence of a recorded step, not the identity of whoever
wrote it. Only `require-signed-receipt` with caller-supplied trusted keys checks an attestation,
and key custody stays with the caller.

## Leases and ceilings

An admission declares a `ceiling` (`:observe`, `:select`, `:construct`). The **signed** lease in
the changeset context must meet it. `AshGraphLaw.Authority` (shared by `Change.Admit` and
`Validation.Admissible`, so both paths judge one lease one way) compares the ceiling the signed
lease claims with the admission's before the engine is called and refuses with `:ceiling_unmet` on
a shortfall. Everything that is not a signed lease grants `:observe`: a bare ceiling atom, a
`%{ceiling: _}` map, an unsigned `:lease`, `:unverified_lease`. A caller cannot write its way to
`:construct`.

The claim is only a pre-check. The engine verifies the signature offline against the resource's
`runtime.trusted_keys` and judges expiry on its own clock in the same request; an admission the
engine did not verify is never `{:ok, _}`, so a forged claim (untrusted signer, tampered body,
expired, upgraded after signing) passes the pre-check and is refused `:lease_refused`.
`trusted_keys` and `max_skew_secs` are taken ONLY from the `runtime` section; `now_unix`, `lease`
and `unverified_lease` are never forwarded, and trust material inside the caller's lease map is
ignored. The library never issues, signs or extends a lease.

`AshGraphLaw.Evidence` records the lease identity (ceiling, lease id, signer key id, SHA-256 of the
canonical signed lease) and the engine's `wasm_sha256`, so the authority behind an admitted change
can be replayed from the record.

## Standing is derived

`AshGraphLaw.Standing.of/1` maps a result to a standing:

| Result | Standing |
|---|---|
| `{:ok, %Admitted{}}` | `:PARTIAL_ALIVE` |
| `{:error, %Refusal{class: :blocked_resource}}` | `:BLOCKED` |
| `{:error, %Refusal{class: :unsupported}}` | `:UNSUPPORTED` |
| any other refusal | `:UNKNOWN` (the typed refusal itself carries the reason) |
| anything else | `:UNKNOWN` |

Standing is computed from a result each time and is never stored in the DSL.

## Why `:ALIVE` is unreachable from admission alone

`:ALIVE` means observed execution on the exact admitted subject. Admission observes a
validation on a projection. The consequence the action is meant to produce has not run when
the admission result exists, so the strongest claim available is `:PARTIAL_ALIVE`. A caller that
wants `:ALIVE` must observe the executed consequence itself and record that separately; the
function `Standing.of/1` has no branch that returns `:ALIVE`.

## Refusals keep their term

Each refusal has a class (`refused_identity`, `refused_structure`, `refused_authority`,
`refused_admission`, `blocked_resource`, `unsupported`) and a `broken_term` from the Chatman
failure taxonomy. A refusal is a typed outcome, not a standing.

## Determinism by projection

`AshGraphLaw.Projection.Default` (`lib/ash_graphlaw/projection/default.ex`) turns a changeset,
query or action input into N-Triples that are de-duplicated and sorted, so the same input always
yields byte-identical text. Determinism here is what makes engine calls comparable across runs
and what makes parity checking (`mix ash_graphlaw.parity`) meaningful: if projections drifted,
two honest runs could disagree for reasons that have nothing to do with the law. Sensitive
attributes are omitted entirely (redaction by omission), never masked in place — a masked value
would still be projected as structure; an omitted one projects nothing.

## Consequences for callers

- Treat `%AshGraphLaw.Admitted{}` as evidence, not permission. Whatever the transition actually
  does must be authorized elsewhere.
- Treat refusals as closed data: match on `code`/`class`, read `details`, keep `raw` for
  diagnostics.
- Do not derive authority from a receipt's `:authority` field — it is a label the engine
  recorded, an observation.
- Gate authority with ceilings and signed leases up front; the engine re-verifies signatures on
  the same request.

## See Also

- [Architecture](architecture.md)
- [Typed refusals](../reference/typed_refusals.md) (generated)
- [Claims and evidence](../reference/claims_and_evidence.md)
