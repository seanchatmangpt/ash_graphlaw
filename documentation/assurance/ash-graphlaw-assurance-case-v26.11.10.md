<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# AshGraphLaw Assurance Case v26.11.10

An argument, with evidence and its standing, that release `26.11.10` does what it says. Every
evidence item names a file. Standing uses `UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`,
`BUILD_BROKEN`, `UNSUPPORTED`.

## Subject

| Item | Value |
|---|---|
| Library | `26.11.10` |
| Engine pin | GraphLaw `v26.11.10`, ABI version 1, sha256 `62cd95d4ef7294dcd5976a2f685b71580bb834816e9f4bba0d13d5555e35c8f8` (`priv/graphlaw/MANIFEST.json`) |
| Registry | `graphlaw.capability-registry/1`, GraphLaw `26.11.10` |
| Receipts | `docs/jira/v26.11.10/RECEIPTS.md` (13 live execution receipts, exit 0) |

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
| G2 | Digest is judged before compile; import surface is a closed allowlist | claims 1 to 3, 31; `test/unit/engine_load_test.exs`, `test/integration/pinned_engine_test.exs` | ALIVE (`docs/jira/v26.11.10/RECEIPTS.md`) |
| G3 | Registry, typed modules, API and examples are compared with the live engine by checks P1 to P9, R1 | claims 36, 42; `test/unit/parity_test.exs`, `test/negative/parity_court_test.exs`; `mix ash_graphlaw.parity` | PARTIAL_ALIVE (court verified, exit 0) |
| G4 | Refusal table is closed; unknown engine kinds map to `:engine_unclassified`; `raw` is lossless | claims 22, 37, 40; `lib/ash_graphlaw/refusal.ex` | PARTIAL_ALIVE |
| G5 | Projections come from ontology.ttl, queries and templates through ggen; --check compares two syncs; the ledger lists residue | `scripts/ggen_sync.sh --check`, `--check-ledger`; [HANDWRITTEN.md](../../HANDWRITTEN.md) | ALIVE |
| G6 | No module implements RDF, SPARQL, SHACL, ShEx, N3, Datalog, entailment or planning; each op builds a request and decodes an answer | `lib/ash_graphlaw/lifecycle.ex`, generated capability modules | ALIVE (verified by audit) |

## Falsifiers

| Claim | What would falsify it |
|---|---|
| G1 | an `{:ok, %Admitted{}}` path that skips the ceiling check, or a standing of `:ALIVE` from `Standing.of/1` |
| G2 | engine bytes with a different sha256 reaching instantiation |
| G3 | the parity court passing while a registry op has no typed module, or failing to fail on an injected drift |
| G4 | a registry refusal code mapping to `:engine_unclassified` (P7) |
| G5 | two syncs producing different bytes, or a hand-written file without a ledger row |
| G6 | a capability module containing evaluation logic for a semantic op |

## Known gaps and non-claims

- The installer `--target` option is `UNSUPPORTED`.
- Atomic actions with external engine calls are `UNSUPPORTED`.
- Live publication to Hex.pm is subject to operator OTP credentials.

## See Also

- [Claims and evidence](../reference/claims_and_evidence.md)
- [Conformance claim](../reference/conformance_claim.md)
- [Capability registry and parity](../topics/capability_registry_and_parity.md)
- [Release Receipts](../../docs/jira/v26.11.10/RECEIPTS.md)
