<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# conformance_claim

What release `26.11.10` claims, and what it does not.

## Claimed

| Claim | Standing |
|---|---|
| Admission through the pinned engine yields typed evidence or a typed refusal, bound to an exact input digest | see [claims and evidence](claims_and_evidence.md) |
| Every GraphLaw op in the vendored registry has a typed module, API function and result decoder, and needs no `call/2` | UNKNOWN until `mix ash_graphlaw.parity` runs against an engine that carries the registry |
| Result decoding is lossless and forward-compatible | see claims 36 to 40 in [claims and evidence](claims_and_evidence.md) |
| Typed refusals form a closed table (40 codes after the capability additions) | see [typed refusals](typed_refusals.md) (generated) |

## Not claimed

- That admission authorizes anything. GraphLaw derives and validates; it never authorizes.
- That any claim is `ALIVE`. No claim has an exact-SHA receipt yet; tokens
  `<<RECEIPT:claim-N>>` mark where the release receipt goes.
- That the engine implements RDF, SPARQL, SHACL, ShEx, N3, Datalog, entailment or planning
  correctly. That is the upstream claim, tested in the GraphLaw repository. AshGraphLaw exposes
  those operations and reimplements none.
- That parity holds against the pinned engine `v26.11.10` on the exact subject without a recorded run of `mix ash_graphlaw.parity`.
- That the installer `--target` option works (`UNSUPPORTED`).
- That any consequence was executed, or that this library signs leases.

## Subject identity

| Item | Value |
|---|---|
| Library | `26.11.10` |
| Engine pin | `v26.11.10`, ABI version 1, sha256 `62cd95d4ef7294dcd5976a2f685b71580bb834816e9f4bba0d13d5555e35c8f8` |
| Registry | `graphlaw.capability-registry/1`, GraphLaw `26.11.10` |
| Exact-SHA receipt | recorded in `docs/jira/v26.11.10/RECEIPTS.md` |

## See Also

- [Claims and evidence](claims_and_evidence.md)
- [Support matrix](support_matrix.md)
- [Assurance case](../assurance/ash-graphlaw-assurance-case-v26.11.10.md)
