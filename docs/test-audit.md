# Test Audit Register

Standing: UNVERIFIED (static audit of test declarations; no consolidation executed yet)

Audit of every `*_test.exs` under `test/`, taken from three read-only passes. Verdict is KEEP or
CONSOLIDATE-INTO (merge unique assertions into a table-driven or existing test; no plain
deletion). Counts are static `test`/`property` declarations, so every "after" is an estimate.
Paths are relative to `test/`.

Flags: DUP duplicate of another file, TAUTOLOGY asserts what it built, NARROW differs only in
input, SLEEP fixed sleep, HELPER re-implemented helper, SKIP skipped test.

## Wave 1 targets (no merging, remove dead weight)

| Item | Where | Action |
|---|---|---|
| 5 skipped tests | `integration/law_test.exs` | un-skipped: reason said engine v26.9.28 ignores leases; pinned 26.11.10 passes all 5 (premise rot, re-pinned) |
| 2 skipped tests | `adversarial/lease_ceiling_test.exs` | same: both pass against the pinned engine |
| Sleep | `unit/host_lifecycle_test.exs:34,94` | done: `test/support/eventually.ex` (deadline poll, the one audited sleep) |
| Sleep | `integration/host_recycle_load_test.exs:129`, `integration/pool_test.exs:31`, `mutation/mutation_engine_test.exs:476` | done: four local counter-based `eventually` helpers replaced by `Eventually.await` |
| Sleep (kept) | `mutation_engine_test.exs:241` (`:infinity` parked owner), `property/pool_property_test.exs:32` (scripted host models work time) | modelling, not coordination; left as is |
| Compiler-proven vacuity | `integration/law_test.exs:71` (`Standing.of(result) == :ALIVE` can never hold) | TAUTOLOGY, fix in the tautology sweep |
| Tautologies | see flags below | remove or replace with a real assertion |

## unit, ash, compat, generated, top level (46 files, 478 to about 321)

| File | Verdict | Target |
|---|---|---|
| ash/atomic_test | CONSOLIDATE | ash/admission_integrations_test (new) |
| ash/calculation_canonical_id_test | CONSOLIDATE | ash/capability_integrations_test (new) |
| ash/calculation_conforms_test | CONSOLIDATE | ash/capability_integrations_test |
| ash/calculation_sparql_test | CONSOLIDATE | ash/capability_integrations_test |
| ash/capability_dsl_test | CONSOLIDATE | unit/authority_test |
| ash/change_canonicalize_test | CONSOLIDATE | ash/capability_integrations_test |
| ash/change_test | CONSOLIDATE | ash/admission_integrations_test |
| ash/dsl_test | CONSOLIDATE | unit/admissions_test |
| ash/preparation_test | CONSOLIDATE | ash/admission_integrations_test |
| ash/refusals_without_engine_test | KEEP | |
| ash/telemetry_test | CONSOLIDATE | ash/admission_integrations_test |
| ash/validation_shacl_test | CONSOLIDATE | ash/capability_integrations_test |
| ash/validation_test | CONSOLIDATE | ash/admission_integrations_test |
| compat/admission_dsl_compat_test | CONSOLIDATE | unit/admissions_test |
| compat/lifecycle_compat_test | CONSOLIDATE | ash/admission_integrations_test |
| compat/raw_call_ops_test | KEEP | |
| compat/root_api_shapes_test | CONSOLIDATE | unit/root_api_test, compat/raw_call_ops_test |
| generated/capability_surface_test | KEEP | generated; do not edit |
| unit/abi_test | KEEP | table the 5 unpack and 5 decode vectors in file |
| unit/admissions_capability_test | KEEP | |
| unit/admissions_test | KEEP | absorbs dsl_test, admission_dsl_compat_test, composition_test |
| unit/authority_test | KEEP | absorbs capability_dsl_test |
| unit/capability_canonical_json_test | KEEP | |
| unit/capability_coerce_test | KEEP | |
| unit/capability_decode_test | KEEP | |
| unit/contract_capability_test | CONSOLIDATE | unit/contract_test |
| unit/contract_test | KEEP | absorbs contract_capability_test |
| unit/engine_load_test | KEEP | |
| unit/evidence_origin_test | CONSOLIDATE | unit/evidence_test |
| unit/evidence_test | KEEP | |
| unit/host_lifecycle_test | KEEP | SLEEP at :34, :94 |
| unit/law_and_projection_test | CONSOLIDATE | unit/projection_origin_test |
| unit/parity_test | KEEP | table the three R3 tests |
| unit/projection_default_test | KEEP | |
| unit/projection_origin_test | KEEP | absorbs law_and_projection_test |
| unit/refusal_raw_test | CONSOLIDATE | unit/refusal_test |
| unit/refusal_test | KEEP | |
| unit/root_api_test | KEEP | absorbs root_api_shapes_test |
| unit/root_capability_delegates_test | KEEP | |
| unit/standing_test | KEEP | stale "35 codes" label |
| unit/telemetry_test | KEEP | |
| unit/template_query_sync_test | KEEP | |
| unit/version_sync_test | KEEP | pins 26.10.28; other files pin 26.11.10 (resolve first) |
| unit/wasm_config_test | KEEP | |
| ash_graphlaw_castle_ocel_projection_test | KEEP | else branch only (ash_a2a absent) |
| ash_graphlaw_composition_test | CONSOLIDATE | unit/admissions_test |

## integration, adversarial, negative (45 files, 364 to about 223)

| File | Verdict | Target |
|---|---|---|
| integration/capability/canonical_test | KEEP | trim 8 to 4 |
| integration/capability/capabilities_test | KEEP | trim 7 to 5 |
| integration/capability/convert_test | CONSOLIDATE | integration/capability/typed_ops_table_test (new) |
| integration/capability/datalog_test | CONSOLIDATE | typed_ops_table_test |
| integration/capability/entail_test | CONSOLIDATE | typed_ops_table_test |
| integration/capability/hooks_test | CONSOLIDATE | typed_ops_table_test |
| integration/capability/law_test | KEEP | trim 15 to 7 |
| integration/capability/n3_test | CONSOLIDATE | typed_ops_table_test |
| integration/capability/op_examples_driver_test | KEEP | merge 3 into 2 |
| integration/capability/parse_test | CONSOLIDATE | typed_ops_table_test |
| integration/capability/policy_test | KEEP | trim 8 to 4 |
| integration/capability/shacl_closed_probe_test | CONSOLIDATE | integration/capability/shacl_test |
| integration/capability/shacl_test | KEEP | absorbs probe, 6 to 4 |
| integration/capability/shex_test | KEEP | trim 8 to 5 |
| integration/capability/sniff_test | CONSOLIDATE | typed_ops_table_test |
| integration/capability/sparql_test | KEEP | trim 9 to 5 |
| integration/admission_differential_test | KEEP | merge 30 and 41 |
| integration/determinism_test | CONSOLIDATE | adversarial/replay_determinism_test |
| integration/engine_admission_test | CONSOLIDATE | negative/engine_load_negative_test |
| integration/fuel_and_response_cap_test | KEEP | 6 to 4 |
| integration/host_recycle_load_test | KEEP | SLEEP at :129 |
| integration/host_test | KEEP | 7 to 3 |
| integration/law_test | KEEP | 5 SKIP; 11 to 6 |
| integration/parity_pinned_engine_test | KEEP | |
| integration/pinned_engine_test | KEEP | 9 to 7 |
| integration/pool_test | KEEP | SLEEP at :31 |
| integration/reactor_capability_test | KEEP | 6 to 4 |
| integration/store_limits_test | KEEP | 9 to 7 |
| adversarial/authority_boundary_test | KEEP | 9 to 8 |
| adversarial/capability_ops_adversarial_test | KEEP | 21 to 16 |
| adversarial/concurrency_test | KEEP | 5 to 3 |
| adversarial/forged_lease_engine_test | KEEP | 5 to 3 plus reason asserts |
| adversarial/hostile_encoding_test | KEEP | 8 to 5 |
| adversarial/lease_ceiling_test | KEEP | 2 SKIP; 13 to 4 |
| adversarial/memory_bomb_test | KEEP | 8 to 5 |
| adversarial/replay_determinism_test | KEEP | 10 to 10 with determinism's two |
| negative/capability_request_negative_test | KEEP | canonical owner of request refusals |
| negative/config_negative_test | KEEP | 8 to 6 |
| negative/contract_negative_test | KEEP | 14 to 10, absorbs dsl_capability |
| negative/dsl_capability_negative_test | CONSOLIDATE | negative/contract_negative_test |
| negative/engine_load_negative_test | KEEP | 11 to 8, absorbs engine_admission |
| negative/parity_court_test | KEEP | 11 to 5 |
| negative/projection_negative_test | KEEP | 11 to 8 |
| negative/refusal_capability_codes_test | CONSOLIDATE | negative/refusal_negative_test |
| negative/refusal_negative_test | KEEP | absorbs capability_codes |

## property, mix, mutation, livebooks (27 files, about 263 to about 175)

| File | Verdict | Target / note |
|---|---|---|
| property/abi_property_test | CONSOLIDATE | self: fold the bad-input and unpack twins |
| property/admissions_property_test | CONSOLIDATE | self: one Contract generator run |
| property/authority_property_test | CONSOLIDATE | self: 10 to 6 |
| property/capability_helpers_property_test | CONSOLIDATE | self |
| property/capability_op_property_test | CONSOLIDATE | self: op x slot table |
| property/pool_property_test | KEEP | SLEEP in the scripted host |
| property/projection_property_test | CONSOLIDATE | self |
| property/refusal_forward_compat_property_test | CONSOLIDATE | property/refusal_property_test |
| property/refusal_property_test | CONSOLIDATE | self; absorbs forward_compat |
| property/standing_property_test | CONSOLIDATE | self |
| property/wasm_config_property_test | CONSOLIDATE | self |
| mix/tasks/ash_graphlaw_install_negative_test | CONSOLIDATE | mix/tasks/install_target_test |
| mix/tasks/ash_graphlaw_install_test | CONSOLIDATE | mix/tasks/install_target_test |
| mix/tasks/install_target_test | CONSOLIDATE | self; single install test, shared setup |
| mix/tasks/mutate_task_subprocess_test | CONSOLIDATE | mix/tasks/mutate_task_test |
| mix/tasks/mutate_task_test | CONSOLIDATE | self; hub with arg and --list tables |
| mix/tasks/parity_test | KEEP | |
| mix/tasks/vendor_download_test | CONSOLIDATE | self; table server behaviours (11 to 7) |
| mix/tasks/vendor_test | CONSOLIDATE | self; table refusals (22 to 14) |
| mix/tasks/verify_and_mutate_test | CONSOLIDATE | mutate half to mutate_task_test; verify half to verify_task_test (new) |
| mutation/catalog_completeness_test | CONSOLIDATE | mutation/mutation_engine_test |
| mutation/mutation_engine_test | CONSOLIDATE | self; absorbs catalog; table qualify verdicts |
| mutation/runner_containment_test | CONSOLIDATE | mutation/runner_redefinition_test |
| mutation/runner_redefinition_test | CONSOLIDATE | self; absorbs containment; keep the two KNOWN GAP tests |
| livebooks/livebook_semantic_integrity_test | CONSOLIDATE | self; merge static scans and the three run tests |

## Findings needing a decision

- `unit/version_sync_test.exs` records `26.10.28`; four other files pin `26.11.10`.
- The Castle OCEL cross-emitter tests only ever take their else branch because `ash_a2a` is not a
  dependency.
- Two KNOWN GAP tests in `mutation/runner_redefinition_test.exs` pin gaps the code still has.

## See Also

`../../.claude/plans/the-point-is-that-jiggly-nebula.md`
