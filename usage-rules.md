<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Rules for working with AshGraphLaw

AshGraphLaw is an Ash extension that hosts the GraphLaw WASM engine (release `v26.9.28`,
ABI version 1; typed capability registry `26.9.29`) and lets an Ash action declare named admissions. GraphLaw derives and
validates; it never authorizes. Nothing in this library grants authority. Admission
evidence is an observation bound to an exact input digest.

AshGraphLaw is not a triplestore, a policy engine, an `Ash.DataLayer`, or an authorization
system. Ash policies still own who may act.

## Core invariant

```text
caller proposes            (Ash changeset / query / input + Law module steps)
      |
      v
Projection                 (deterministic N-Triples; input_digest = sha256 of the text)
      |
      v
GraphLaw WASM              (derives and validates; pinned sha256, admitted before start)
      |
      v
AshGraphLaw                (transports and projects typed success or typed refusal)
      |
      +--> {:ok, %Admitted{}}    -> Evidence, standing :PARTIAL_ALIVE at most
      +--> {:error, %Refusal{}}  -> code, class, broken_term
```

The caller proposes. GraphLaw derives and validates. The library transports and projects a
typed result. No step in this chain authorizes anything.

## Rules by concern

| Concern | Rule |
|---|---|
| Installation, config keys, runtime boundary | [setup.md](usage-rules/setup.md) |
| The `graphlaw` DSL section and entities | [dsl.md](usage-rules/dsl.md) |
| Change/Validation/Preparation, Law, Projection | [admission.md](usage-rules/admission.md) |
| WASM engine load, Host, Pool, limits | [wasm-host.md](usage-rules/wasm-host.md) |
| Closed refusal table, standing vocabulary | [refusals.md](usage-rules/refusals.md) |
| Chicago tests, `:wasm` tag, mutation | [testing.md](usage-rules/testing.md) |
| ggen manufacturing, generated vs hand files | [ggen.md](usage-rules/ggen.md) |
| Leases, ceilings, trust anchors | [authority.md](usage-rules/authority.md) |
| Evidence, standing vocabulary, receipts | [evidence-standing.md](usage-rules/evidence-standing.md) |
| `vendor`, `verify`, `parity`, `mutate`, scripts | [mix-tasks.md](usage-rules/mix-tasks.md) |
| The mutation court | [mutation.md](usage-rules/mutation.md) |
| Deploying and operating | [production.md](usage-rules/production.md) |
| Sources versus projections | [ontology-first.md](usage-rules/ontology-first.md) |
| Atomic actions and engine-backed calculations | [actions-and-atomics.md](usage-rules/actions-and-atomics.md) |
| Typed capability API and results | [capabilities.md](usage-rules/capabilities.md) |
| The capability parity court | [parity.md](usage-rules/parity.md) |
| Validations, changes, calculations, Reactor steps | [lifecycle.md](usage-rules/lifecycle.md) |

## Non-negotiables

- Never treat `{:ok, %AshGraphLaw.Admitted{}}` as authorization or as `ALIVE`.
- Never hand-edit a generated file; edit `ontology.ttl`, `queries/`, `templates/`,
  `ggen.toml` and run `scripts/ggen_sync.sh` (`scripts/vendor_marketplace.sh` first when `vendor/` is absent).
- Never call generated `AshGraphLaw.Resource.Info` from hand-written code; use
  `AshGraphLaw.Admissions`.
- Never mock the engine, the Host, or Ash. Use the real pinned WASM.
- Never call `AshGraphLaw.call/2` for an op that has a typed capability; never reimplement RDF,
  SPARQL, SHACL, ShEx, N3, Datalog, entailment or planning semantics.
- Never add a skip or an allow-list to the parity court.
- Never write `ALIVE` without an exact-SHA receipt.
- Refusals are typed values. Match on `code`, `class`, `broken_term`; never on message text.

## See Also

[AGENTS.md](AGENTS.md) - [documentation/README.md](documentation/README.md)
