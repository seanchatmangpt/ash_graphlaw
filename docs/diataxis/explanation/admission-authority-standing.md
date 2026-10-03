<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Explanation: Admission, Authority and Standing

Why `ash_graphlaw` is shaped the way it is. This page explains the model; the how-to
([declare and wire admissions](../how-to/declare-and-wire-admissions.md)) shows the mechanics.

## One membrane, not a reimplementation

`ash_graphlaw` is the Ash/BEAM membrane for GraphLaw. Semantic standards — RDF, SPARQL, SHACL,
ShEx, N3, RDFS, OWL-RL, hooks, plan admission, receipts — stay inside the pinned
`graphlaw.wasm` module, hosted through Wasmex with GraphLaw's JSON ABI preserved
(`lib/ash_graphlaw/host.ex`, `lib/ash_graphlaw/pool.ex`, `lib/ash_graphlaw/abi.ex`). The
Elixir side projects outcomes into typed structs; it never reimplements the semantics. This is
why the capability surface is generated from GraphLaw's capability registry
(`lib/ash_graphlaw/capability/registry.ex`, `mix ash_graphlaw.parity` fails on drift) rather
than hand-written per op: one law, many runtimes, no N-squared drift between engine and client.

## The core invariant: derives and validates, never authorizes

A caller proposes a request; the engine decides whether the projected semantic state and the
requested transition are admitted. The library projects exactly two outcomes:

- `{:ok, %AshGraphLaw.Admitted{}}` — digest-bound evidence of admission on one exact input
  (`lib/ash_graphlaw/admitted.ex`);
- `{:error, %AshGraphLaw.Refusal{}}` — a closed refusal `code` with a `class` and a
  `broken_term` from the Chatman failure taxonomy (`lib/ash_graphlaw/refusal.ex`).

Nothing in this flow grants authority. `AshGraphLaw.Receipt` records what the engine observed —
parent/child state ids, triples added, the lease id under which a step ran — and the module doc
states it plainly: "It records what happened; it grants no authority"
(`lib/ash_graphlaw/receipt.ex`).

## Why ceilings and leases are separate from admission

Admission answers "is this transition consistent with the law?". Authority answers "may this
caller act at this level?". These are different questions, so they get different machinery.
`AshGraphLaw.Authority` (`lib/ash_graphlaw/authority.ex`) defines a three-level ceiling order
`:observe < :select < :construct`:

- `:observe` — read-only ops; needs no lease.
- `:select` — for example `:plan`.
- `:construct` — graph-building ops (`:n3`, `:entail`, `:datalog`, `:hooks`, `:law`).

Before the engine is even called, `check_ceiling/2` compares the declared admission ceiling with
the lease carried in changeset context (`:graphlaw_lease` by default). An unmet ceiling refuses
with `:ceiling_unmet` before any bytes reach the engine — a fail-fast refusal that saves a round
trip and, more importantly, keeps authority checking out of the engine's hands: the engine
verifies lease signatures and expiry against the resource's `runtime.trusted_keys`, and trust
anchors, skew and the clock are never taken from changeset context
(`lib/ash_graphlaw/change/admit.ex`, "Lease context key").

Only a `:signed_lease` entry (`%{"lease" => ..., "attestation" => ...}`) can raise the ceiling
above `:observe`. A bare ceiling atom or an unsigned map grants only `:observe`. This is the
structural reason `AshGraphLaw.Standing` never reports `:ALIVE` for an admission alone:
admission evidence is an observation bound to an exact input digest, and standing is a property
of a witnessed execution with authority, not of a validation result.

## Standing as a vocabulary, not a status flag

`AshGraphLaw.Standing` (`lib/ash_graphlaw/standing.ex`) defines six values — `:UNKNOWN,
:PARTIAL_ALIVE, :ALIVE, :BLOCKED, :BUILD_BROKEN, :UNSUPPORTED` — and `Standing.of/1` maps a
result onto them:

```elixir
{:ok, %AshGraphLaw.Admitted{}}                    #=> :PARTIAL_ALIVE
{:error, %AshGraphLaw.Refusal{class: :blocked_resource}} #=> :BLOCKED
{:error, %AshGraphLaw.Refusal{class: :unsupported}}      #=> :UNSUPPORTED
{:error, %AshGraphLaw.Refusal{}}                  #=> :UNKNOWN
_                                                 #=> :UNKNOWN
```

There is no mapping from admission success to `:ALIVE`. That absence is deliberate: claiming
ALIVE requires an observed execution on the exact subject with authority, which admission
evidence alone cannot carry. Keeping the vocabulary closed and the mapping total means callers
cannot silently widen an observation into an authority claim.

## Refusals as a closed vocabulary

Every failure is one of the codes in `AshGraphLaw.Refusal.codes/0`, and every code maps to
exactly one class (`:refused_admission, :refused_authority, :blocked_resource, :refused_structure,
:unsupported, :refused_identity`) and one `broken_term` (`:mu_on_O, :R_missing_authority,
:R_missing_consequence, :R_missing_standing, :R_missing_identity, :admission_vacuous`).
`class_of/1` raises on an unknown code — the vocabulary cannot be extended by passing a new atom.
A closed refusal taxonomy means downstream code can pattern-match on `class` and `broken_term`
without string parsing, and the `raw` field keeps the untouched engine error so nothing is lost
by projection.

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
