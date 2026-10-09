<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# wasm_host_design

Why `AshGraphLaw.Host` is shaped the way it is. The design follows the hardening lessons of the
`ash_a2a` WASM host and the GraphLaw ABI rules in the
[ABI reference](../reference/abi_reference.md).

## Admission before instantiation

`AshGraphLaw.EngineLoad.admit/2` runs before `Wasmex.start_link`, in this order:

1. digest pin (`:wasm_digest_mismatch`), when a hex pin is expected. Hashing is cheap and compiling
   untrusted bytes is not, so a pinned load of a foreign module costs one sha256 and never reaches
   the Wasmtime compiler. With `expected_sha256: :unpinned` the caller chose the bytes and steps 2
   to 4 are the only gates;
2. compile and inspect the module (`:wasm_invalid`);
3. import surface: every import must be a function in the manifest's closed allowlist
   (`glx:WasiImport` rows in `ontology.ttl`, projected to `host_abi.imports`), matched by module,
   name AND type (`:wasm_import_surface_mismatch`; `details.unexpected` lists foreign modules,
   `details.unexpected_functions` lists offending `module.function` entries). `path_open`,
   `sock_*` and the rest of WASI are refused even though their module is `wasi_snapshot_preview1`;
4. required exports `gl_alloc`, `gl_call`, `gl_free`, `memory` (`:wasm_missing_export`).

A missing or unusable allowlist refuses every engine. Because these checks precede
instantiation, a foreign module cannot crash the caller or run a single instruction.

## Pin rules (SC-04)

- The pinned digest is the release asset for `v26.9.28`, recorded in `priv/graphlaw/MANIFEST.json`.
- Path resolution order: `opts[:wasm_path]`, `GRAPHLAW_WASM_PATH`, application config, then the
  vendored `priv/graphlaw/graphlaw.wasm`.
- A path from the environment or config stays pinned, so the environment cannot swap the engine.
- An explicit `opts[:wasm_path]` that differs from the vendored path is `:unpinned` unless the
  caller also passes `expected_sha256`.
- The vendor task downloads the release asset and checks `sha256sum --strict` against the
  manifest before the file is used. The binary is never shipped in the hex package.

## One transaction at a time

`gl_alloc`, write, `gl_call`, read and `gl_free` share one linear memory. Interleaving two
requests would corrupt buffers, so one outer GenServer serializes the whole transaction.
Parallelism comes from `AshGraphLaw.Pool`, which runs N independent hosts under a
`:rest_for_one` supervisor and picks one per request.

## Guards

| Guard | Behaviour |
|---|---|
| UTF-8 | Text that is not valid UTF-8 is refused as `:invalid_encoding` by the ABI codec before the engine sees it |
| Fuel | Fuel per call is `timeout_ms * fuel_per_ms` (default 5,000 * 1,000,000 = 5,000,000,000; instantiate 1,000,000,000); exhaustion is `:fuel_exhausted` |
| Memory limit | Store limit 268,435,456 bytes; growth beyond it fails the call |
| Store limits | table_elements 100,000, instances 10, tables 10, memories 4: growth beyond them is denied by wasmtime |
| Response size | A response over max_response_bytes (33,554,432) is :resource_limit before it is copied out of engine memory; the engine buffer is still freed |
| Queue | max_queue 64. Shed as :saturated at two points: by the caller (mailbox length read before enqueueing, against the caller's own limits; best-effort, concurrent callers can briefly exceed it) and by the host itself, which refuses a dequeued request without running it when its own configured max_queue callers are already waiting behind it |
| Timeout | timeout_ms default 5,000; expiry is :call_timeout |
| Null alloc | gl_alloc returning null is a resource-limit refusal |
| Request size | Encoded requests above 16 MiB are `:resource_limit` before the call |

## Recycle

The instance is replaced on `abi_failure`, `call_exited`, a trap, a timeout, fuel exhaustion, or
when linear memory exceeds `recycle_bytes` (default 134,217,728). Recycling emits
`[:ash_graphlaw, :host, :recycle]`. A crashed engine never leaves a poisoned instance serving the
next request.

The caller is answered BEFORE the recycle starts (`GenServer.reply/2`, then recycle). A recycle runs
`_initialize` again, which can take seconds; answering afterwards would turn a typed refusal into
`:call_timeout` for the caller. The next call queues behind the recycle.

## Init never crashes

If the module is absent, unreadable or fails admission, `init` still succeeds. The host enters an
`{:unavailable, %Refusal{}}` state and every call returns that refusal (for example
`:wasm_not_vendored`). A library that is compiled but not yet vendored therefore loads cleanly
and fails per request with a typed reason. `_initialize` is called once when exported.

An unavailable host is not dead. It retries the load with capped exponential backoff
(`retry_base_ms` 500, `retry_max_ms` 30,000), so a transient failure (a slow `_initialize`, a
vendor run that finishes later) heals without a restart. In a pool it leaves the `:members`
registration while unavailable, so it never wins the shortest-mailbox pick; with no live member the
caller gets the unavailable member's own typed refusal.

## Pool is opt-in

`AshGraphLaw.Application` starts the pool only when `config :ash_graphlaw, start_pool: true`.
By default nothing is started, so applications control when a WASM instance is created.

## See Also

- [ABI reference](../reference/abi_reference.md)
- [Architecture](architecture.md)
- [Typed refusals](../reference/typed_refusals.md) (generated)
