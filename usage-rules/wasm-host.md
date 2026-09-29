<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Wasm Host

## Engine admission

`AshGraphLaw.EngineLoad.admit/2` runs before `Wasmex.start_link`, in this order:
compile/inspect, import-surface check (every import must be module
`wasi_snapshot_preview1`), required exports (`gl_alloc gl_call gl_free memory`), sha256 pin.
Refusals: `:wasm_invalid`, `:wasm_import_surface_mismatch`, `:wasm_missing_export`,
`:wasm_digest_mismatch`. A foreign module therefore cannot crash the caller.

## Host and Pool

- `AshGraphLaw.Host` is a GenServer serializing the alloc/write/call/read/free transaction.
  `init` never crashes; failure becomes an unavailable state returning the `%Refusal{}`.
- `Host.request/3` returns `{:ok, decoded_map}` (response `ok` true or false) or
  `{:error, %Refusal{}}` for transport/host failures only.
- `AshGraphLaw.Pool` is a `:rest_for_one` supervisor of N Hosts (default
  `System.schedulers_online()`); member 0 is registered as `AshGraphLaw.Host`.
- Recycling occurs on `abi_failure`, `call_exited`, trap, timeout, fuel exhaustion, or memory above
  `recycle_bytes`; the caller is answered before the recycle starts.
- A host whose load or recycle failed is unavailable, not dead: it retries with capped backoff and
  is not routed to by the pool while unavailable.
- Load shedding returns `:saturated` past `max_queue`: a best-effort caller-side pre-check plus a
  host-side check with the host's own configured bound, so `max_queue` given to `Host`/`Pool` bites.

## Limits (defaults)

| Limit | Default |
|---|---|
| fuel per call | `timeout_ms * fuel_per_ms` (5_000 * 1_000_000 = 5_000_000_000) |
| instantiate fuel | 1_000_000_000 |
| memory_limit_bytes | 268_435_456 |
| recycle_bytes | 134_217_728 |
| max_queue | 64 |
| timeout_ms | 5_000 |
| request size | 16 MiB (`:resource_limit`) |
| max_response_bytes | 33_554_432 (`:resource_limit`) |
| table_elements / instances / tables / memories | 100_000 / 10 / 10 / 4 |

## Rules

- Do run `mix ash_graphlaw.vendor` before expecting real admissions.
- Do use `AshGraphLaw.call/2` and friends; do not send raw bytes to Wasmex.
- Do not lower or remove the digest pin to make a test pass. Fix the asset instead.
- Do not treat `:call_timeout`, `:saturated`, `:fuel_exhausted` as admission outcomes.
  They are `blocked_resource`: the observation did not happen.
- Text that is not valid UTF-8 is refused with `:invalid_encoding` by the ABI codec before it
  reaches the engine.
- The engine import surface is a closed allowlist by module, name and type; a pinned load is judged
  on its digest before the bytes are compiled.
- Whether the pinned release asset exists at the pinned URL with the pinned digest is
  UNKNOWN until `mix ash_graphlaw.vendor` succeeds.

## Telemetry

`[:ash_graphlaw, :host, :call, :stop]`, `[:ash_graphlaw, :host, :recycle]`,
`[:ash_graphlaw, :engine, :admit]`.

## See Also

[setup.md](setup.md) - [refusals.md](refusals.md) - [../usage-rules.md](../usage-rules.md)
