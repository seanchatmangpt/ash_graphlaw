<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# AshGraphLaw Assurance Case v26.9.29

An argument, with evidence and its standing, that release `26.9.29` does what it says. Every
evidence item names a file. Standing uses `UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`,
`BUILD_BROKEN`, `UNSUPPORTED`. No item is `ALIVE`: there is no exact-SHA receipt
(`<<RECEIPT:claim-4>>`).

## Subject

> Point-in-time record for release `26.9.29` (engine pin `v26.9.28` at that time). The current
> engine pin is `v26.9.29` — an intentional pin, see CHANGELOG 26.10.8.

| Item | Value |
|---|---|
| Library | `26.9.29`, working tree, no release SHA |
| Engine pin | GraphLaw `v26.9.28`, ABI version 1, sha256 `30f6bc6e...` (`priv/graphlaw/MANIFEST.json`) |
| Registry | `graphlaw.capability-registry/1`, GraphLaw `26.9.29` |

## Top claim

AshGraphLaw hosts the pinned GraphLaw engine, exposes its operations as typed Ash-facing
capabilities, and returns evidence or a typed refusal without granting authority.

## Argument

```text
G0 top claim
|- G1 authority is never granted
|- G2 the engine identity is pinned and checked
|- G3 every registry op is reachable through a typed API (parity)
|- G4 failures are typed, closed and forward-compatible
|- G5 generated code is generated, residue is ledgered
'- G6 semantics are exposed, not reimplemented
```

| Goal | Argument | Evidence | Standing |
|---|---|---|---|
| G1 | Only a signed lease raises the ceiling; the pre-check runs before the engine; standing never returns ALIVE for an admission | claims 13 to 17, 21 in [claims and evidence](../reference/claims_and_evidence.md); `test/unit/authority_test.exs`, `test/unit/standing_test.exs` | PARTIAL_ALIVE |
| G2 | Digest is judged before compile; import surface is a closed allowlist | claims 1 to 3, 31; `test/unit/engine_load_test.exs` | PARTIAL_ALIVE (pinned engine itself: UNKNOWN) |
| G3 | Registry, typed modules, API and examples are compared with the live engine by checks P1 to P9, R1 | claims 36, 42; `test/unit/parity_test.exs`, `test/negative/parity_court_test.exs`, `test/integration/parity_pinned_engine_test.exs` | UNKNOWN: court not run; pinned engine predates the registry |
| G4 | Refusal table is closed; unknown engine kinds map to `:engine_unclassified`; `raw` is lossless | claims 22, 37, 40 | UNKNOWN for 37, 40; PARTIAL_ALIVE for 22 |
| G5 | Projections come from ontology.ttl, queries and templates through ggen; --check compares two syncs; the ledger lists residue | `scripts/ggen_sync.sh --check`, `--check-ledger`; [HANDWRITTEN.md](../../HANDWRITTEN.md) | UNKNOWN: not run for this page |
| G6 | No module implements RDF, SPARQL, SHACL, ShEx, N3, Datalog, entailment or planning; each op builds a request and decodes an answer | `lib/ash_graphlaw/lifecycle.ex`, generated capability modules | UNKNOWN: an inspection claim, no automated check |

## Falsifiers

| Claim | What would falsify it |
|---|---|
| G1 | an `{:ok, %Admitted{}}` path that skips the ceiling check, or a standing of `:ALIVE` from `Standing.of/1` |
| G2 | engine bytes with a different sha256 reaching instantiation |
| G3 | the parity court passing while a registry op has no typed module, or failing to fail on an injected drift (the mutation catalog carries such mutants: `test/mutation/`) |
| G4 | a registry refusal code mapping to `:engine_unclassified` (P7) |
| G5 | two syncs producing different bytes, or a hand-written file without a ledger row |
| G6 | a capability module containing evaluation logic for a semantic op |

## Known gaps and non-claims

- Parity against `v26.9.28` is not established; the pin bump is a separate serialized step.
- The installer `--target` option is `UNSUPPORTED`.
- Atomic actions are `UNSUPPORTED`.
- Reactor steps require the optional `:reactor` dependency; their tests are UNKNOWN.
- No claim is `ALIVE`.

## See Also

- [Claims and evidence](../reference/claims_and_evidence.md)
- [Conformance claim](../reference/conformance_claim.md)
- [Capability registry and parity](../topics/capability_registry_and_parity.md)
