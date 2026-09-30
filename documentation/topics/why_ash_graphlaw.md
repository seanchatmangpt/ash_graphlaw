<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# why_ash_graphlaw

Why an Ash application would add AshGraphLaw, and when it should not.

## The problem it addresses

An Ash action changes data or answers a query. Sometimes the acceptance rule is a statement about
a graph: a SHACL shape, an N3 rule, a plan whose preconditions must hold. GraphLaw evaluates those
in a pinned WASM engine. AshGraphLaw lets an action name such a rule and receive either evidence or
a typed refusal, without the application embedding an RDF stack.

## Admission versus Ash policies

| | Ash policy | AshGraphLaw admission |
|---|---|---|
| Question | Who may perform this action? | Does this projected subject pass this law step? |
| Input | actor, tenant, resource | projected N-Triples of the changeset, query or input |
| Decision by | Ash policy checks | the pinned GraphLaw engine |
| Output | authorized or forbidden | `Evidence` (observation) or typed `Refusal` |
| Authority | yes | never |

They compose: a policy decides who may act; an admission observes whether the subject satisfies
the law. An admitted action is not an authorized action.

## Beside `ash_r2rml`

`ash_r2rml` is an Ash extension that compiles Ash resources into W3C R2RML mappings so the same
subject is exposed as RDF while the data layer stays relational. AshGraphLaw takes a subject (by
projection) and evaluates law steps over it. The first produces RDF from Ash; the second checks
RDF derived from Ash. They are independent libraries; whether they are used together in one
application is not covered by any test here (UNKNOWN).

## What 26.9.29 adds

The typed capability surface: the ops of the engine beyond `law`, as typed functions, result structs
and Ash lifecycle modules. AshGraphLaw exposes these; it implements no RDF, SPARQL, SHACL, ShEx, N3,
Datalog, entailment or planning semantics. See
[capability registry and parity](capability_registry_and_parity.md).

## When not to use it

- You need authorization. Use Ash policies; nothing here grants authority.
- You need a triplestore or an `Ash.DataLayer`. This is neither.
- Your rule is one attribute constraint. An Ash validation is smaller.
- You need atomic updates over admitted actions. Admission needs a WASM call and is not atomic.
- You cannot vendor and run a WASI engine on your target.

## See Also

- [Architecture](architecture.md)
- [Authority boundary](authority_boundary.md)
- [Support matrix](../reference/support_matrix.md)
