# ash_graphlaw reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### AshGraphLaw.Refusal

| `abi_failure` | function | abi_failure/2 |  |  |  |  |

| `abi_version_mismatch` | function | abi_version_mismatch/2 |  |  |  |  |

| `broken_term_of` | function | broken_term_of/1 |  |  |  |  |

| `broken_terms` | function | broken_terms/0 |  |  |  |  |

| `build` | function | build/3 |  |  |  |  |

| `call_exited` | function | call_exited/2 |  |  |  |  |

| `call_timeout` | function | call_timeout/2 |  |  |  |  |

| `call_trapped` | function | call_trapped/2 |  |  |  |  |

| `capability_not_declared` | function | capability_not_declared/2 |  |  |  |  |

| `capability_parity_drift` | function | capability_parity_drift/2 |  |  |  |  |

| `capability_response_undecodable` | function | capability_response_undecodable/2 |  |  |  |  |

| `ceiling_unmet` | function | ceiling_unmet/2 |  |  |  |  |

| `class_of` | function | class_of/1 |  |  |  |  |

| `classes` | function | classes/0 |  |  |  |  |

| `codes` | function | codes/0 |  |  |  |  |

| `doc_of` | function | doc_of/1 |  |  |  |  |

| `duplicate_admission` | function | duplicate_admission/2 |  |  |  |  |

| `engine_refused` | function | engine_refused/2 |  |  |  |  |

| `engine_unclassified` | function | engine_unclassified/2 |  |  |  |  |

| `from_engine` | function | from_engine/2 |  |  |  |  |

| `fuel_exhausted` | function | fuel_exhausted/2 |  |  |  |  |

| `host_not_started` | function | host_not_started/2 |  |  |  |  |

| `instantiation_failed` | function | instantiation_failed/2 |  |  |  |  |

| `invalid_capability_request` | function | invalid_capability_request/2 |  |  |  |  |

| `invalid_encoding` | function | invalid_encoding/2 |  |  |  |  |

| `invalid_json` | function | invalid_json/2 |  |  |  |  |

| `invalid_runtime_option` | function | invalid_runtime_option/2 |  |  |  |  |

| `invalid_trusted_key` | function | invalid_trusted_key/2 |  |  |  |  |

| `law_module_failed` | function | law_module_failed/2 |  |  |  |  |

| `lease_refused` | function | lease_refused/2 |  |  |  |  |

| `malformed_response` | function | malformed_response/2 |  |  |  |  |

| `message` | function | message/1 |  |  |  |  |

| `missing_law_module` | function | missing_law_module/2 |  |  |  |  |

| `new` | function | new/3 |  |  |  |  |

| `not_admitted` | function | not_admitted/2 |  |  |  |  |

| `plan_refused` | function | plan_refused/2 |  |  |  |  |

| `policy_refused` | function | policy_refused/2 |  |  |  |  |

| `projection_failed` | function | projection_failed/2 |  |  |  |  |

| `receipt_required` | function | receipt_required/2 |  |  |  |  |

| `resource_limit` | function | resource_limit/2 |  |  |  |  |

| `saturated` | function | saturated/2 |  |  |  |  |

| `unknown_admission` | function | unknown_admission/2 |  |  |  |  |

| `unknown_capability` | function | unknown_capability/2 |  |  |  |  |

| `unsupported_step` | function | unsupported_step/2 |  |  |  |  |

| `wasm_digest_mismatch` | function | wasm_digest_mismatch/2 |  |  |  |  |

| `wasm_import_surface_mismatch` | function | wasm_import_surface_mismatch/2 |  |  |  |  |

| `wasm_invalid` | function | wasm_invalid/2 |  |  |  |  |

| `wasm_missing_export` | function | wasm_missing_export/2 |  |  |  |  |

| `wasm_not_vendored` | function | wasm_not_vendored/2 |  |  |  |  |

| `wasm_unreadable` | function | wasm_unreadable/2 |  |  |  |  |

| `broken_term` | type | @type broken_term :: :mu_on_O | :R_missing_authority | :R_missing_consequence | :R_missing_standing | :R_missing_identity | :admission_vacuous |  |  |  |  |

| `class` | type | @type class :: :refused_admission | :refused_authority | :blocked_resource | :refused_structure | :unsupported | :refused_identity |  |  |  |  |

| `code` | type | @type code :: :not_admitted | :plan_refused | :receipt_required | :lease_refused | :resource_limit | :policy_refused | :engine_refused | :engine_unclassified | :wasm_not_vendored | :wasm_unreadable | :wasm_invalid | :wasm_digest_mismatch | :wasm_import_surface_mismatch | :wasm_missing_export | :abi_version_mismatch | :instantiation_failed | :abi_failure | :call_trapped | :call_exited | :call_timeout | :saturated | :host_not_started | :fuel_exhausted | :invalid_encoding | :invalid_json | :malformed_response | :unknown_admission | :duplicate_admission | :missing_law_module | :invalid_runtime_option | :invalid_trusted_key | :ceiling_unmet | :projection_failed | :law_module_failed | :unsupported_step | :invalid_capability_request | :unknown_capability | :capability_not_declared | :capability_parity_drift | :capability_response_undecodable |  |  |  |  |

| `t` | type | @type t :: %__MODULE__{ code: code(), class: class(), kind: String.t() | nil, engine: String.t() | nil, dialect: String.t() | nil, message: String.t(), details: map(), broken_term: broken_term(), raw: map() | nil } |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `abi_failure` | function | abi_failure/2 |  |  |  |  |

| `abi_version_mismatch` | function | abi_version_mismatch/2 |  |  |  |  |

| `broken_term_of` | function | broken_term_of/1 |  |  |  |  |

| `broken_terms` | function | broken_terms/0 |  |  |  |  |

| `build` | function | build/3 |  |  |  |  |

| `call_exited` | function | call_exited/2 |  |  |  |  |

| `call_timeout` | function | call_timeout/2 |  |  |  |  |

| `call_trapped` | function | call_trapped/2 |  |  |  |  |

| `capability_not_declared` | function | capability_not_declared/2 |  |  |  |  |

| `capability_parity_drift` | function | capability_parity_drift/2 |  |  |  |  |

| `capability_response_undecodable` | function | capability_response_undecodable/2 |  |  |  |  |

| `ceiling_unmet` | function | ceiling_unmet/2 |  |  |  |  |

| `class_of` | function | class_of/1 |  |  |  |  |

| `classes` | function | classes/0 |  |  |  |  |

| `codes` | function | codes/0 |  |  |  |  |

| `doc_of` | function | doc_of/1 |  |  |  |  |

| `duplicate_admission` | function | duplicate_admission/2 |  |  |  |  |

| `engine_refused` | function | engine_refused/2 |  |  |  |  |

| `engine_unclassified` | function | engine_unclassified/2 |  |  |  |  |

| `from_engine` | function | from_engine/2 |  |  |  |  |

| `fuel_exhausted` | function | fuel_exhausted/2 |  |  |  |  |

| `host_not_started` | function | host_not_started/2 |  |  |  |  |

| `instantiation_failed` | function | instantiation_failed/2 |  |  |  |  |

| `invalid_capability_request` | function | invalid_capability_request/2 |  |  |  |  |

| `invalid_encoding` | function | invalid_encoding/2 |  |  |  |  |

| `invalid_json` | function | invalid_json/2 |  |  |  |  |

| `invalid_runtime_option` | function | invalid_runtime_option/2 |  |  |  |  |

| `invalid_trusted_key` | function | invalid_trusted_key/2 |  |  |  |  |

| `law_module_failed` | function | law_module_failed/2 |  |  |  |  |

| `lease_refused` | function | lease_refused/2 |  |  |  |  |

| `malformed_response` | function | malformed_response/2 |  |  |  |  |

| `message` | function | message/1 |  |  |  |  |

| `missing_law_module` | function | missing_law_module/2 |  |  |  |  |

| `new` | function | new/3 |  |  |  |  |

| `not_admitted` | function | not_admitted/2 |  |  |  |  |

| `plan_refused` | function | plan_refused/2 |  |  |  |  |

| `policy_refused` | function | policy_refused/2 |  |  |  |  |

| `projection_failed` | function | projection_failed/2 |  |  |  |  |

| `receipt_required` | function | receipt_required/2 |  |  |  |  |

| `resource_limit` | function | resource_limit/2 |  |  |  |  |

| `saturated` | function | saturated/2 |  |  |  |  |

| `unknown_admission` | function | unknown_admission/2 |  |  |  |  |

| `unknown_capability` | function | unknown_capability/2 |  |  |  |  |

| `unsupported_step` | function | unsupported_step/2 |  |  |  |  |

| `wasm_digest_mismatch` | function | wasm_digest_mismatch/2 |  |  |  |  |

| `wasm_import_surface_mismatch` | function | wasm_import_surface_mismatch/2 |  |  |  |  |

| `wasm_invalid` | function | wasm_invalid/2 |  |  |  |  |

| `wasm_missing_export` | function | wasm_missing_export/2 |  |  |  |  |

| `wasm_not_vendored` | function | wasm_not_vendored/2 |  |  |  |  |

| `wasm_unreadable` | function | wasm_unreadable/2 |  |  |  |  |

| `broken_term` | type | @type broken_term :: :mu_on_O | :R_missing_authority | :R_missing_consequence | :R_missing_standing | :R_missing_identity | :admission_vacuous |  |  |  |  |

| `class` | type | @type class :: :refused_admission | :refused_authority | :blocked_resource | :refused_structure | :unsupported | :refused_identity |  |  |  |  |

| `code` | type | @type code :: :not_admitted | :plan_refused | :receipt_required | :lease_refused | :resource_limit | :policy_refused | :engine_refused | :engine_unclassified | :wasm_not_vendored | :wasm_unreadable | :wasm_invalid | :wasm_digest_mismatch | :wasm_import_surface_mismatch | :wasm_missing_export | :abi_version_mismatch | :instantiation_failed | :abi_failure | :call_trapped | :call_exited | :call_timeout | :saturated | :host_not_started | :fuel_exhausted | :invalid_encoding | :invalid_json | :malformed_response | :unknown_admission | :duplicate_admission | :missing_law_module | :invalid_runtime_option | :invalid_trusted_key | :ceiling_unmet | :projection_failed | :law_module_failed | :unsupported_step | :invalid_capability_request | :unknown_capability | :capability_not_declared | :capability_parity_drift | :capability_response_undecodable |  |  |  |  |

| `t` | type | @type t :: %__MODULE__{ code: code(), class: class(), kind: String.t() | nil, engine: String.t() | nil, dialect: String.t() | nil, message: String.t(), details: map(), broken_term: broken_term(), raw: map() | nil } |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
