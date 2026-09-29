<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# architecture

`ash_graphlaw` puts a WebAssembly build of GraphLaw behind Ash actions. An action's subject is
projected to RDF, the engine derives or validates over it, and the result comes back as either
evidence or a typed refusal.

## Layers

```text
  Ash.Resource  +  AshGraphLaw.Resource   (Spark extension: section :graphlaw)
        |
        |   action declares  change / validate / prepare
        v
  AshGraphLaw.Change.Admit | Validation.Admissible | Preparation.Admit
        |   Admissions.fetch  ->  ceiling check (before any engine call)
        v
  AshGraphLaw.Projection  (Default: sorted N-Triples, dialect "ntriples")
        |   input_digest = sha256(projected text)
        |   Law.steps(subject, admission)
        v
  AshGraphLaw.law/3  ->  AshGraphLaw.call/2  ->  ABI.encode_request
        v
  AshGraphLaw.Pool  (Supervisor; N hosts; Registry)
        v
  AshGraphLaw.Host  (GenServer; one transaction at a time)
        v
  graphlaw.wasm  (pinned release v26.9.28; ABI_VERSION 1)
        |   PurRDF: SHACL, SPARQL, RDFS/OWL-RL, Datalog   Eyeron: N3
        v
  {:ok, %Admitted{}} | {:error, %Refusal{}}
        v
  %Evidence{}  in changeset context   |   Ash error carrying the Refusal
```

## Compile time

The Spark extension declares the `graphlaw` section with the `runtime` and `admission` entities.
A persister and verifier run at compile time; the verifier delegates to
`AshGraphLaw.Contract.validate/1`, so a malformed admission fails the build, not a request.
Hand-written code reads admissions through `AshGraphLaw.Admissions`.

## Run time

1. The action runs its `Admit` change (or validation, or query preparation).
2. The admission is looked up by name; the lease in the changeset context is compared with the
   admission `ceiling`. A shortfall is refused as `:ceiling_unmet` without touching the engine.
3. The projection turns the subject into RDF text. Its sha256 becomes the `input_digest`.
4. The `Law` module supplies the step maps. `AshGraphLaw.law/3` sends them to the pool.
5. The engine returns receipts and states, or a refusal. The library never guesses: an engine
   refusal it cannot classify becomes `:engine_unclassified`.
6. On success an `Evidence` value is stored in the changeset context. On refusal an error
   carrying the `%Refusal{}` is added to the changeset, which halts the action.

## Where each concern lives

| Concern | Module |
|---|---|
| Wire format | `AshGraphLaw.ABI` |
| Engine identity | `AshGraphLaw.EngineLoad`, `AshGraphLaw.WasmConfig` |
| Instance lifecycle | `AshGraphLaw.Host`, `AshGraphLaw.Pool` |
| Failure vocabulary | `AshGraphLaw.Refusal`, `AshGraphLaw.Error.Refused` |
| Observation record | `AshGraphLaw.Evidence`, `AshGraphLaw.Receipt`, `AshGraphLaw.Admitted` |
| Derived standing | `AshGraphLaw.Standing` |

## Telemetry

`[:ash_graphlaw, :host, :call, :stop]`, `[:ash_graphlaw, :host, :recycle]`,
`[:ash_graphlaw, :engine, :admit]`, `[:ash_graphlaw, :admission, :stop]`. No other events.

## See Also

- [Authority boundary](authority_boundary.md)
- [WASM host design](wasm_host_design.md)
- [Generation and residue](generation_and_residue.md)
- [ABI reference](../reference/abi_reference.md)
