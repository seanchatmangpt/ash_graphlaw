<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# configuration

Keys under `config :ash_graphlaw`, environment variables, and the `runtime` DSL fields.

## Application config

| Key | Type | Default | Meaning |
|---|---|---|---|
| `start_pool` | boolean | `false` | Start `AshGraphLaw.Pool` under the application. |
| `pool` | keyword | `[]` | Options forwarded to `AshGraphLaw.Pool.start_link/1` (`size`, host options). |
| `wasm_path` | string | none | Path to the engine. Still pinned to the manifest digest. |

## Environment

| Variable | Meaning |
|---|---|
| `GRAPHLAW_WASM_PATH` | Engine path; outranks `config :ash_graphlaw, :wasm_path`. Still pinned. |

Path resolution order: `opts[:wasm_path]`, `GRAPHLAW_WASM_PATH`, application config,
`priv/graphlaw/graphlaw.wasm` in the app dir. An explicit `opts[:wasm_path]` different from the
vendored path is unpinned unless `opts[:expected_sha256]` is also given.

## Resource limits

Resolved by `AshGraphLaw.WasmConfig.limits/1` in the order call options, `config :ash_graphlaw`,
default. `fuel` defaults to `timeout_ms * fuel_per_ms`.

| Key | Default |
|---|---|
| `timeout_ms` | `5_000` |
| `fuel_per_ms` | `1_000_000` |
| `instantiate_fuel` | `1_000_000_000` |
| `memory_limit_bytes` | `268_435_456` |
| `recycle_bytes` | `134_217_728` |
| `max_queue` | `64` |
| `max_response_bytes` | `33_554_432` |
| `table_elements` | `100_000` |
| `instances` | `10` |
| `tables` | `10` |
| `memories` | `4` |

## Call options

`AshGraphLaw.call/2` and every typed op accept `:server` (default `AshGraphLaw.Pool`), `:timeout`,
`:fuel`. Lifecycle modules read only `:server` and `:timeout` from their options.

## `runtime` DSL fields

| Field | Default |
|---|---|
| `wasm_path` | `nil` |
| `timeout_ms` | `5000` |
| `max_skew_secs` | `60` |
| `trusted_keys` | `[]` |

Trust anchors come only from `trusted_keys`; caller context cannot add to them. See
[DSL reference](dsl_reference.md).

## Pin

`priv/graphlaw/MANIFEST.json` (generated) holds the engine release tag, `artifact.url`,
`artifact.sha256` and the WASI import allowlist. Current pin: `v26.9.28`,
sha256 `30f6bc6eca9d125fe805f4c2643818ebb0a1471edec75ed0ed989c734397c645`.

## See Also

- [Run the pool](../how_to/run_the_pool.md)
- [Vendor the WASM](../how_to/vendor_the_wasm.md)
- [Usage rule: setup](../../usage-rules/setup.md)
