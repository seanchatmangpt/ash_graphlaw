<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# claims_and_evidence

Every claim this library makes, the test file that demonstrates it, its standing, and its limits.
Standing vocabulary: `UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`, `BUILD_BROKEN`,
`UNSUPPORTED`. `ALIVE` means observed execution on an exact admitted subject (a commit SHA plus the
pinned engine identity).

## How the statuses were produced

`PARTIAL_ALIVE` below means: the named test file exists, and was executed by `mix test` on the
working tree that produced this page. That tree was not yet a commit, so no exact-SHA receipt
exists, and the pinned `graphlaw.wasm` (sha256 in `priv/graphlaw/MANIFEST.json`) was not vendored
in that environment, so every `:wasm`-tagged test was excluded with a printed reason. A claim whose
only demonstration is a `:wasm` test is `UNKNOWN`. No claim is `ALIVE`.

Where a claim has two halves, the status is the weaker one and the limits column names the half
that did not run.

## Qualification run against a local, unpinned GraphLaw build

Because the pinned asset was not available, the `:wasm` and `:slow` tests were also run once
against a local GraphLaw build: `git describe` `v26.9.28-17-g4acb6cb`, sha256
`356cc48aa1e8968e8176310ba745ce6a863e6d32efd7a4c783a96ce59d9ebd63`, `wasm32-wasip1`, profile `wasm`.
To make the pin machinery accept it, only the copy of `MANIFEST.json` inside the Mix build directory
was pointed at that digest; no source file, no pin and no library code was changed for the run.

Result: 462 tests, 13 failures (`mix test --include slow --cover`, 75.5% coverage). All 13 failures
are assertions that the pin equals the literal `30f6bc6e...` (`wasm_config_test.exs`,
`config_negative_test.exs`, `engine_load_test.exs`), which is exactly what a swapped pin breaks and
what proves those tests bite. Every other test passed, including forged-lease refusal by the engine,
the 100-way concurrent admission, saturation, fuel exhaustion and determinism. This is evidence about
that build, not about the pinned asset: no claim below is upgraded by it, and claims whose only
demonstration is a `:wasm` test stay `UNKNOWN` for the pinned engine.

## Claims

| # | Claim | Test files | Status | Limits |
|---|---|---|---|---|
| 1 | The engine bytes must match the pinned sha256 before they are compiled or instantiated | `test/unit/engine_load_test.exs`, `test/negative/engine_load_negative_test.exs`, `test/unit/wasm_config_test.exs` | PARTIAL_ALIVE | Synthetic real modules only; the pinned engine itself was not loaded |
| 2 | A pinned load of foreign bytes is refused `:wasm_digest_mismatch` without invoking the Wasmtime compiler (bytes that cannot compile still get the digest refusal) | `test/unit/engine_load_test.exs`, `test/negative/engine_load_negative_test.exs` | PARTIAL_ALIVE | Shows compile did not run by outcome, not by tracing |
| 3 | The engine import surface is a closed allowlist of `{name, params, results}` from `MANIFEST.json` (`glx:WasiImport` rows); other functions and wrong types are refused and named | `test/unit/engine_load_test.exs`, `test/negative/engine_load_negative_test.exs` | PARTIAL_ALIVE | The allowlist was read off a local GraphLaw build (17 commits past v26.9.28), not the pinned asset: UNKNOWN whether the pinned engine fits it |
| 4 | A response larger than `max_response_bytes` is refused `:resource_limit` before it is copied out of engine memory | `test/unit/host_lifecycle_test.exs` | PARTIAL_ALIVE | Scripted engine, not GraphLaw |
| 5 | Table growth is bounded by `table_elements`; `memories`, `instances`, `tables` and `memory_limit_bytes` are applied through wasmtime store limits | `test/unit/host_lifecycle_test.exs`, `test/adversarial/memory_bomb_test.exs` | PARTIAL_ALIVE | Only `table_elements` and the response cap are shown to bite; the others are passed through unexercised |
| 6 | Fuel defaults to `timeout_ms * fuel_per_ms` | `test/unit/wasm_config_test.exs` | PARTIAL_ALIVE | Fuel exhaustion against the real engine: `test/integration/host_test.exs`, UNKNOWN |
| 7 | The caller receives a trap's typed refusal before the recycle runs (a slow `_initialize` cannot turn it into `:call_timeout`) | `test/unit/host_lifecycle_test.exs` | PARTIAL_ALIVE | Falsified against the old order: the same test fails at 1501 ms when the reply follows the recycle |
| 8 | A host whose load or recycle failed retries with capped backoff and heals; it never dies | `test/unit/host_lifecycle_test.exs` | PARTIAL_ALIVE | |
| 9 | An unavailable pool member is never routed to while a live one exists; with none live the caller gets the member's real refusal | `test/unit/host_lifecycle_test.exs` | PARTIAL_ALIVE | Pick is best-effort: the mailbox length is read before the call is enqueued |
| 9b | A host sheds `:saturated` with its own configured `max_queue` even when callers pass none (the caller-side pre-check alone never fired) | `test/unit/host_lifecycle_test.exs`, `test/integration/pool_test.exs` | PARTIAL_ALIVE | The unit half uses a scripted slow engine; the pool test is `:wasm` |
| 10 | Host serializes alloc/write/call/read/free for the real engine; the pool serves concurrent callers | `test/integration/host_test.exs`, `test/integration/pool_test.exs`, `test/adversarial/concurrency_test.exs` | UNKNOWN | `:wasm` only |
| 11 | Missing wasm degrades to typed `:wasm_not_vendored`, not a crash | `test/unit/host_lifecycle_test.exs`, `test/ash/atomic_test.exs` | PARTIAL_ALIVE | |
| 12 | Text that is not valid UTF-8 is refused `:invalid_encoding` by the ABI codec before any byte reaches the engine, and is not echoed | `test/unit/abi_test.exs`, `test/adversarial/memory_bomb_test.exs` | PARTIAL_ALIVE | Real-engine memory bound: `test/integration/host_test.exs`, UNKNOWN |
| 13 | Only a signed lease raises the authority above `:observe`; a bare atom, `%{ceiling: _}`, an unsigned `:lease`, or context under another key grants nothing | `test/unit/authority_test.exs`, `test/adversarial/lease_ceiling_test.exs` | PARTIAL_ALIVE | The pre-check only |
| 14 | `ceiling_unmet` is returned before any engine call, by both the change and the validation path (one shared `AshGraphLaw.Authority`) | `test/adversarial/lease_ceiling_test.exs`, `test/ash/change_test.exs` | PARTIAL_ALIVE | `test/ash/validation_test.exs` and `preparation_test.exs` are `:wasm`, UNKNOWN |
| 15 | Trust anchors and skew come only from the resource `runtime`; `now_unix`, `lease` and `unverified_lease` from caller context are never forwarded | `test/unit/authority_test.exs` | PARTIAL_ALIVE | The engine-side refusal of a caller-supplied anchor is UNKNOWN (`:wasm`) |
| 16 | A forged signed lease (untrusted signer, expired, tampered, upgraded after signing) is refused `:lease_refused` by the engine and admits nothing | `test/adversarial/lease_ceiling_test.exs`, `test/integration/law_test.exs` | UNKNOWN | `:wasm`: needs the engine to verify Ed25519 |
| 17 | Evidence records the engine `wasm_sha256` and the presented lease identity (ceiling, lease id, signer key id, lease digest); it accepts no free-form lease or extra option | `test/unit/evidence_test.exs`, `test/adversarial/authority_boundary_test.exs`, `test/unit/authority_test.exs` | PARTIAL_ALIVE | `wasm_sha256` is filled from the host at admission time: UNKNOWN (`:wasm`) |
| 18 | `AshGraphLaw.Change.Admit` refuses a violating action and leaves no data-layer write | `test/ash/change_test.exs` | UNKNOWN | `:wasm`; Ets data layer only |
| 19 | Evidence is bound to the sha256 of the projected N-Triples | `test/unit/evidence_test.exs`, `test/integration/determinism_test.exs` | PARTIAL_ALIVE | Observation only; not authorization |
| 20 | `Projection.Default` is deterministic and never emits sensitive attributes or sensitive arguments | `test/unit/projection_default_test.exs`, `test/negative/projection_negative_test.exs` | PARTIAL_ALIVE | |
| 21 | `Standing.of/1` never returns `:ALIVE` for an admission result | `test/unit/standing_test.exs` | PARTIAL_ALIVE | Property of the derivation function |
| 22 | Refusal codes, classes and broken terms form a closed table; a known engine kind without a table code is `:engine_refused`, an unknown one is `:engine_unclassified` | `test/unit/refusal_test.exs`, `test/negative/refusal_negative_test.exs` | PARTIAL_ALIVE | Table is generated from `ontology.ttl` |
| 23 | `Contract.validate/1` rejects duplicate admissions, missing or `steps/2`-less law modules, bad keys and options, and a malformed compiled state; it is fail-closed | `test/unit/contract_test.exs`, `test/negative/contract_negative_test.exs` | PARTIAL_ALIVE | Compile-time refusals are observed on Spark's stderr (Spark prints verifier errors from a checker process) |
| 24 | Real engine admits a conforming subject and refuses a violating one (SHACL) and a plan at its first unmet precondition | `test/integration/law_test.exs`, `test/integration/engine_admission_test.exs` | UNKNOWN | `:wasm` |
| 25 | `mix ash_graphlaw.vendor` keeps a candidate only when its sha256 is the pin, installs it atomically, and never destroys an existing pin-verified engine on a mismatch | `test/mix/tasks/vendor_test.exs` | PARTIAL_ALIVE | Local files only; the network fetch was not run |
| 26 | The mutation runner compiles only files under `test/` (no symlinks) and refuses a file that redefines a module loaded from outside `test/` | `test/mutation/runner_containment_test.exs` | PARTIAL_ALIVE | |
| 27 | `mix ash_graphlaw.mutate` kills every registered mutant (14 catalog entries) | `lib/mix/tasks/ash_graphlaw.mutate.ex`, `test/mutation/mutation_engine_test.exs` | PARTIAL_ALIVE | 14 of 14 `mutant_killed` with `:wasm` killers excluded; run on the uncommitted tree |
| 28 | The installer adds the formatter plugin and the `wasmex` dependency, and its `--target` patch path is known to fail | `test/mix/tasks/ash_graphlaw_install_test.exs`, `test/mix/tasks/ash_graphlaw_install_negative_test.exs` | UNSUPPORTED | The pack's `add_extension/1` inserts unparsable code (SyntaxError); recorded as `UNSUPPORTED(generator-capability)` |
| 29 | The generated typed-refusal reference lists every code in the ontology | `gates/020_refusal_code_contract.rq` run by `ggen sync` | PARTIAL_ALIVE | Run under ggen 26.9.28 on the uncommitted tree |
| 30 | The library ships no wasm binary in the hex package | `mix hex.build` file list | PARTIAL_ALIVE | `files:` in the generated `mix.exs`; `priv/graphlaw/.gitignore` excludes `*.wasm` |
| 31 | GraphLaw is pinned to release v26.9.28, ABI_VERSION 1, and that release asset matches the manifest sha256 | `ontology.ttl`, `priv/graphlaw/MANIFEST.json` (generated) | UNKNOWN | The release asset at the pinned URL was not fetched here: it could not be admitted from a local build |
| 32 | No authority is granted by the library: evidence is an observation | `documentation/topics/authority_boundary.md`; module docs | PARTIAL_ALIVE | Enforced by claims 13 to 17 and 21 |
| 33 | The root API turns response bytes into typed values: `"ok": true` is `{:ok, map}`, an error object is a typed refusal with its details, anything else is `:malformed_response`; host failures pass through | `test/unit/root_api_test.exs` | PARTIAL_ALIVE | Scripted engine answers, so this shows classification, not what GraphLaw answers |
| 34 | `mix ash_graphlaw.verify` admits the vendored engine, checks its ABI version against the manifest and refuses each failure with a typed code | `test/mix/tasks/verify_and_mutate_test.exs` | PARTIAL_ALIVE | Scripted engines in a scratch project; the pinned engine was not verified |
| 35 | `Validation.Admissible` and `Preparation.Admit` refuse before the engine on authority, on an unknown admission, and with `:host_not_started` when no host runs | `test/ash/refusals_without_engine_test.exs` | PARTIAL_ALIVE | Their engine-backed paths are `:wasm` (`validation_test.exs`, `preparation_test.exs`), UNKNOWN |

## Reading the table

- A claim is only as strong as the exact subject it ran on. A test that passes on a sibling
  checkout or a different wasm digest does not raise the standing of the subject.
- `:wasm` tests are excluded, with a printed stderr line, when the pinned binary is absent.
  An excluded test contributes nothing to standing.
- Host lifecycle tests use a scripted engine, `AshGraphLaw.Test.WasmFixtures.scripted_engine/1`: a
  spec-valid module run by the real Wasmtime that scripts a trap, a slow `_initialize`, an
  oversized response or a table-growth attempt. It shows how the host behaves at those ABI edges;
  it says nothing about GraphLaw.
- Not claimed anywhere: that admission executed a consequence, that a lease was signed by this
  library, or that the engine implements a standard correctly (that is the upstream engines'
  claim, tested in the GraphLaw repository).

## See Also

- [Support matrix](support_matrix.md)
- [Authority boundary](../topics/authority_boundary.md)
- [Typed refusals](typed_refusals.md) (generated)
