<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Run the Pool

Start N supervised WASM hosts behind one name.

## Start from configuration

```elixir
import Config

config :ash_graphlaw, start_pool: true
config :ash_graphlaw, pool: [size: 4]
```

`start_pool` defaults to `false`; with it off, depending on the library starts no engine.
`pool` options are forwarded to `AshGraphLaw.Pool.start_link/1`.

## Start under your own supervisor

```elixir
children = [
  {AshGraphLaw.Pool, size: 4, timeout_ms: 5_000}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

`:size` defaults to `System.schedulers_online()`. Host options (`:wasm_path`, `:fuel`,
`:memory_limit_bytes`, `:recycle_bytes`, `:max_queue`, `:timeout_ms`, `:expected_sha256`) are
passed to every member. Defaults come from `AshGraphLaw.WasmConfig.limits/1`.

## Call it

The default server is `AshGraphLaw.Pool`:

```elixir
{:ok, caps} = AshGraphLaw.capabilities([])
{:ok, caps} = AshGraphLaw.capabilities(server: AshGraphLaw.Pool, timeout: 10_000)
```

## What to expect

- One host serializes each allocate/write/call/read/free transaction; the pool adds hosts, not
  concurrency inside one host.
- A missing or foreign WASM does not crash startup: each call returns a typed refusal such as
  `:wasm_not_vendored` or `:wasm_digest_mismatch`.
- A full queue returns `:saturated`; a host exceeding its limits is recycled. Exact recycling
  behavior under load is UNKNOWN until the `:wasm` tests report it.
- Telemetry: `[:ash_graphlaw, :host, :call, :stop]` and `[:ash_graphlaw, :host, :recycle]`.

## See Also

- [Vendor the WASM](vendor_the_wasm.md)
- [Handle Refusals](handle_refusals.md)
- [Getting Started](../tutorials/getting_started.md)
