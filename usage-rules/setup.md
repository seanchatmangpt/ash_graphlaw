<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Setup

## Install

- Add `{:ash_graphlaw, "~> 26.9"}` to `deps`. Its runtime deps are `ash`, `spark`, `jason`,
  `wasmex` and `telemetry`; `igniter` is optional.
- Prefer `mix igniter.install ash_graphlaw` when Igniter is present. The installer task is
  generated (`Mix.Tasks.AshGraphlaw.Install`).
- Add `AshGraphLaw.Resource` to the `extensions:` list of each resource that declares
  admissions. Add `AshGraphLaw.Formatter` locations via `import_deps [:ash, :spark]` and
  `Spark.Formatter` in `.formatter.exs`.

## Vendor the WASM engine

- The `.wasm` binary is not shipped in the package. Run `mix ash_graphlaw.vendor` to fetch
  the pinned release asset and verify it against `priv/graphlaw/MANIFEST.json`.
- Downloading requires explicit consent from the person running it. Do not run it
  unprompted.
- Do not commit `priv/graphlaw/*.wasm`; it is gitignored.
- Do not substitute the locally built, unreleased GraphLaw binary. The pin is the release
  asset digest in `MANIFEST.json`.

## Configuration keys

| Key | Meaning |
|---|---|
| `config :ash_graphlaw, start_pool: true` | Start `AshGraphLaw.Pool` under the application. Default `false`. |
| `config :ash_graphlaw, wasm_path: "..."` | Path to the engine. Still pinned to the manifest digest. |
| `GRAPHLAW_WASM_PATH` | Environment override. Still pinned; it cannot swap the engine. |

Path resolution order: `opts[:wasm_path]`, then `GRAPHLAW_WASM_PATH`, then application
config, then `priv/graphlaw/graphlaw.wasm` in the app dir.

- An explicit `opts[:wasm_path]` that differs from the vendored path is unpinned unless the
  caller also passes `opts[:expected_sha256]`. Do not use that outside tests.
- Default server name is `AshGraphLaw.Pool`. Start it yourself in a supervision tree, or set
  `start_pool: true`.

## Runtime boundary

- Every call crosses into WASM through one `AshGraphLaw.Host` transaction
  (alloc, write, call, read, free). Do not call `Wasmex` directly.
- If the wasm is missing, Host starts in an unavailable state and returns
  `{:error, %Refusal{code: :wasm_not_vendored}}` for every call. It does not crash the
  supervision tree.

## See Also

[wasm-host.md](wasm-host.md) - [ggen.md](ggen.md) - [../usage-rules.md](../usage-rules.md)
