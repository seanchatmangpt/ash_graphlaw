<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Vendor the WASM

Place the pinned `graphlaw.wasm` in `priv/graphlaw/` so the host can load it.

## Fetch and verify

```bash
mix ash_graphlaw.vendor
```

The task reads the URL and SHA-256 from `priv/graphlaw/MANIFEST.json`. It keeps the file only when
its SHA-256 equals the pin; otherwise it deletes the candidate and exits non-zero. The download
needs network access and your consent to fetch a binary.

## Use a local file

```bash
mix ash_graphlaw.vendor --from /path/to/graphlaw.wasm
```

The copy is kept only when its digest matches the pin.

## Check without writing

```bash
mix ash_graphlaw.vendor --check
```

Exits non-zero on absence or digest drift. Suitable for CI.

## Point at another location

`AshGraphLaw.WasmConfig.wasm_path/1` resolves, in order: `opts[:wasm_path]`, the
`GRAPHLAW_WASM_PATH` environment variable, `config :ash_graphlaw, :wasm_path`, then
`priv/graphlaw/graphlaw.wasm` in the app. A path from the environment or config stays pinned to
the manifest digest. An explicit `opts[:wasm_path]` differing from the vendored path is unpinned
unless `opts[:expected_sha256]` is given.

## Failure modes

A missing file gives `:wasm_not_vendored`; a digest that differs gives `:wasm_digest_mismatch`.
Both are typed `AshGraphLaw.Refusal` values, not crashes.

## See Also

- [Getting Started](../tutorials/getting_started.md)
- [Run the Pool](run_the_pool.md)
- [Typed Refusals](../reference/typed_refusals.md)
