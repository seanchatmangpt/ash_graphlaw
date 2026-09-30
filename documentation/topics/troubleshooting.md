<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# troubleshooting

Symptom, cause, fix. Refusal codes are the closed table in
[typed refusals](../reference/typed_refusals.md) (generated).

## Refusals

| Code | Cause | Fix |
|---|---|---|
| `:wasm_not_vendored` | no engine at the resolved path | `mix ash_graphlaw.vendor` |
| `:wasm_digest_mismatch` | bytes differ from the pinned sha256 | re-vendor; do not substitute a local build |
| `:wasm_import_surface_mismatch` | engine imports something outside the allowlist | use the pinned release asset |
| `:abi_version_mismatch` | engine `abi_version` differs from the library's | use the matching engine release |
| `:host_not_started` | no pool or host running | set `start_pool: true` or supervise `AshGraphLaw.Pool` |
| `:saturated` | host queue full (`max_queue`) | size the pool up or shed load |
| `:fuel_exhausted`, `:call_timeout` | request exceeded fuel or time | raise `timeout_ms` or reduce input |
| `:ceiling_unmet` | lease claims less than the admission or capability ceiling | present a signed lease with a higher ceiling |
| `:lease_refused` | engine rejected the lease | read `details["reason"]` |
| `:invalid_capability_request` | unknown key, missing field or wrong type | read `details`: `unknown_keys`, `missing`, `type_errors` |
| `:unknown_capability` | op name not in the registry | use `Registry.names/0` |
| `:capability_not_declared` | resource declares capabilities but not this op | add `capability :op` or declare none |
| `:capability_response_undecodable` | engine answer is not a JSON object or not the shape a lifecycle module needs | inspect `details`, `refusal.raw` |
| `:capability_parity_drift` | typed surface differs from the live engine | read the failing check ids in `parity_report.json` |
| `:engine_unclassified` | engine refusal kind this version does not know | read `refusal.raw`; upgrade the library |
| `:projection_failed` | projection raised or returned an unexpected value | fix the projection |

## Symptoms

| Symptom | Cause | Fix |
|---|---|---|
| `:wasm` tests skipped | engine not vendored | `mix ash_graphlaw.vendor` |
| `mix ash_graphlaw.parity` raises `[wasm_not_vendored]` | the court never skips | vendor the engine |
| parity reports `P3` `UNKNOWN` for `registry_sha256` | engine older than `v26.9.29` | expected against the `v26.9.28` pin |
| `Ash.bulk_update` refused | admission is not atomic | `require_atomic? false`, `strategy: :stream` |
| `ggen_sync.sh` exit 3 | vendored marketplace sha differs from `ontology.ttl` | `scripts/vendor_marketplace.sh` |
| `ggen_sync.sh --check-ledger` exit 7 | a residue path is missing from `HANDWRITTEN.md` | add the row |
| generated capability modules missing | `scripts/ggen_sync.sh` not run | run it; never write them by hand |
| installer `--target` raises `SyntaxError` | known pack defect (`UNSUPPORTED`) | add the extension by hand |
| Reactor step returns `"Reactor library is not loaded"` | optional `:reactor` absent | add the dependency |

## See Also

- [Handle refusals](../how_to/handle_refusals.md)
- [Run the parity court](../how_to/run_the_parity_court.md)
- [Configuration](../reference/configuration.md)
