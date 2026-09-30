<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# AshGraphLaw Documentation Hub (Diataxis Framework)

AshGraphLaw (library `26.9.29`, engine pin `v26.9.28`) lets an Ash action declare a named
admission that a pinned GraphLaw WASM engine derives and validates against the action's projected
data. A refusal is a typed value. An admission is an observation bound to one exact input digest
and grants no authority.

The documentation follows the [Diataxis framework](https://diataxis.fr/) in four quadrants:

```text
               LEARNING-ORIENTED          MOSTLY PRACTICAL
                       |                         |
  TUTORIALS -----------+----------- HOW-TO GUIDES
                       |
 ----------------------+-------------------------
                       |
  REFERENCE -----------+----------- EXPLANATION (TOPICS)
                       |
                MOSTLY THEORETICAL       UNDERSTANDING-ORIENTED
```

Standing vocabulary used throughout: `UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`,
`BUILD_BROKEN`, `UNSUPPORTED`. No page claims `ALIVE` without an exact-SHA receipt; pending
evidence is marked with a `<<RECEIPT:claim-N>>` token until the release receipt supplies it.

---

## 1. Tutorials (Learning-Oriented)

Hands-on lessons. Do them in order.

- [Getting Started](tutorials/getting_started.md) - Add the dependency, vendor and verify the
  pinned WASM, start the pool, make the first `capabilities` call.
- [First Admitted Action](tutorials/first_admitted_action.md) - Declare an admission, attach
  `AshGraphLaw.Change.Admit`, write a law module, observe Evidence and a typed refusal.
- [Admit Your First Resource End to End](tutorials/admit_your_first_resource_end_to_end.md) - A
  complete application: domain, resource, law, signed lease, evidence, refusals and a test.
- [Canonical Runnable Livebook](../ash_graphlaw.livemd) - Interactive end-to-end sandbox.

---

## 2. How-To Guides (Task-Oriented)

Recipes for one task each.

Setup and engine:

- [Vendor the WASM](how_to/vendor_the_wasm.md) - Fetch, verify and check the pinned engine.
- [Install with Igniter](how_to/install_with_igniter.md) - Run the generated installer.
- [Run the Pool](how_to/run_the_pool.md) - Start and size `AshGraphLaw.Pool`.

Declaring and gating actions:

- [Declare an Admission](how_to/declare_an_admission.md) - Add a `graphlaw` section and attach it
  to an action.
- [Write a Law Module](how_to/write_a_law_module.md) - Implement `AshGraphLaw.Law` steps and data.
- [Mint and Verify a Signed Lease](how_to/mint_and_verify_a_signed_lease.md) - Produce the lease a
  ceiling demands and check it.
- [Use Validation and Preparation](how_to/use_validation_and_preparation.md) - Admit through
  `Validation.Admissible` and `Preparation.Admit`.
- [Use Atomic Actions](how_to/use_atomic_actions.md) - Admission and `require_atomic?`.

Outcomes and operations:

- [Handle Refusals](how_to/handle_refusals.md) - Recover the typed `Refusal` from an Ash error.
- [Replay Admission Evidence](how_to/replay_admission_evidence.md) - Recompute and compare the
  input digest and evidence digest.
- [Observe with Telemetry](how_to/observe_with_telemetry.md) - Attach handlers to the four events.
- [Test Resources That Use Admissions](how_to/test_resources_that_use_admissions.md) - Chicago
  style tests with a real host.
- [Run the Mutation Catalog](how_to/run_the_mutation_catalog.md) - `mix ash_graphlaw.mutate`, its
  verdicts and `--require-killed`.
- [Regenerate with ggen](how_to/regenerate_with_ggen.md) - Edit ontology and templates, then sync.
- [Release a Version](how_to/release_a_version.md) - The release ladder for a tagged version.

Livebooks (run in Livebook or through `mix ash_graphlaw.test_livebooks`):

- [Ash First](how_to/ash_first.livemd)
- [Handle Refusals Interactively](how_to/handle_refusals_interactively.livemd)
- [Replayable Admission Evidence](how_to/replayable_admission_evidence.livemd)

---

## 3. Reference (Information-Oriented)

Specifications and tables.

- [API Reference](reference/api_reference.md) - Public modules and functions.
- [Configuration](reference/configuration.md) - `config :ash_graphlaw` keys and `runtime` fields.
- [DSL Reference](reference/dsl_reference.md) - The `graphlaw` section, `runtime` and `admission`.
- [DSL Cheat Sheet](reference/dsl_cheatsheet.md) - One-page summary of the DSL.
- [Generated DSL Cheat Sheet](dsls/DSL-AshGraphLaw.Resource.md) - Produced by
  `mix spark.cheat_sheets`.
- [ABI Reference](reference/abi_reference.md) - Request and response envelope of the engine.
- [Typed Refusals](reference/typed_refusals.md) - Generated closed table of refusal codes.
- [Telemetry](reference/telemetry.md) - Events, measurements and metadata.
- [Mix Tasks](reference/mix_tasks.md) - `vendor`, `verify`, `mutate`, `install`, `test_livebooks`
  and the repository scripts.
- [Claims and Evidence](reference/claims_and_evidence.md) - Each claim, its test, status, limits.
- [Conformance Claim](reference/conformance_claim.md) - What this release claims and does not.
- [Support Matrix](reference/support_matrix.md) - Supported and unsupported surfaces.
- [Assurance Case](assurance/ash-graphlaw-assurance-case-v26.9.29.md) - Argument and evidence for
  the `26.9.29` release.
- Usage rules ([index](../usage-rules.md)):
  [setup](../usage-rules/setup.md), [dsl](../usage-rules/dsl.md),
  [admission](../usage-rules/admission.md), [wasm-host](../usage-rules/wasm-host.md),
  [refusals](../usage-rules/refusals.md), [testing](../usage-rules/testing.md),
  [ggen](../usage-rules/ggen.md), [authority](../usage-rules/authority.md),
  [evidence-standing](../usage-rules/evidence-standing.md),
  [mix-tasks](../usage-rules/mix-tasks.md), [mutation](../usage-rules/mutation.md),
  [production](../usage-rules/production.md),
  [ontology-first](../usage-rules/ontology-first.md),
  [actions-and-atomics](../usage-rules/actions-and-atomics.md).

---

## 4. Explanation / Topics (Understanding-Oriented)

Why the library is shaped as it is.

- [Why AshGraphLaw](topics/why_ash_graphlaw.md) - Admission versus Ash policies, side by side with
  `ash_r2rml`, and when not to use it.
- [Architecture](topics/architecture.md) - Layers from Ash action to WASM host.
- [Authority Boundary](topics/authority_boundary.md) - Why admission evidence is not authority.
- [Security Model](topics/security_model.md) - Signed lease, trusted keys, skew, digest pin and
  import allowlist.
- [WASM Host Design](topics/wasm_host_design.md) - Digest pin, import surface, recycling, shedding.
- [Generation and Residue](topics/generation_and_residue.md) - What ggen projects and what is
  hand-written.
- [Upgrading](topics/upgrading.md) - Moving from a pre-release to `26.9.29` and bumping the engine
  pin.
- [Troubleshooting](topics/troubleshooting.md) - Refusal code, cause, fix.

---

## Project Files

- [Changelog](../CHANGELOG.md) - Keep-a-Changelog history; the `26.9.29` entry.
- [Security Policy](../SECURITY.md) - Reporting and supported versions.
- [Contributing](../CONTRIBUTING.md) - Gates a change must pass.
- [Agent Instructions](../AGENTS.md) - Rules for automated contributors.
- [Reproduce](../REPRODUCE.md) - Rebuild the release from its pins.
- [Handwritten Residue](../HANDWRITTEN.md) - Every hand-written file and why no generator emits it.

---

## Product Boundary Invariant

```text
   Ash action (create / update / destroy / read)
                     |
                     v
        AshGraphLaw admission (declared)
                     |
                     v
      GraphLaw derives and validates (WASM)
                     |
                     v
   Evidence or typed Refusal (observation only)

   authority never flows from GraphLaw
```

GraphLaw derives and validates; it never authorizes. Authority comes from a signed lease supplied
by the caller and is checked against the admission `ceiling` before the engine is called. Ash
policies still decide who may act.

AshGraphLaw is not an `Ash.DataLayer`, a triplestore, a policy engine or an authorization system.
