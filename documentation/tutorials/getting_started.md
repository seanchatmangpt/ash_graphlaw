<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Getting Started

By the end you will have added `:ash_graphlaw` `26.9.30`, vendored and verified the pinned
GraphLaw engine (release `v26.9.28`), started the pool and made one `capabilities` call. Every
step below is a command or snippet you run yourself; the tutorial states what to look for, not
output it did not observe.

## 1. Add the dependency

```elixir
def deps do
  [
    {:ash, "~> 3.33"},
    {:ash_graphlaw, "~> 26.9.30"}
  ]
end
```

```bash
mix deps.get
```

The library depends on `wasmex` for the WebAssembly runtime. The Igniter installer can add it and
the formatter plugin for you; see [Install with Igniter](../how_to/install_with_igniter.md).

## 2. Vendor the engine

The engine binary is not shipped in the Hex package. The pin (release tag, URL and SHA-256) is
recorded in `priv/graphlaw/MANIFEST.json`. Fetch the file and check it:

```bash
mix ash_graphlaw.vendor
mix ash_graphlaw.vendor --check
```

`mix ash_graphlaw.vendor` downloads the release asset over HTTPS, writes it to a temporary file,
re-hashes it and renames it into `priv/graphlaw/graphlaw.wasm` only when the SHA-256 equals the
pin. `--check` writes nothing and exits non-zero when the file is absent or its digest differs.
To use a file you already downloaded, pass `--from PATH`. See
[Vendor the WASM](../how_to/vendor_the_wasm.md).

Then admit the engine and run one real call through it:

```bash
mix ash_graphlaw.verify
```

The task applies the digest pin, the import allowlist and the required-export check, starts a
real host, sends `capabilities` and requires the reported `abi_version` to equal the manifest's.
A non-zero exit carries a typed refusal code. A pass is an observation about those bytes and
grants nothing. Standing of this step in this release: `UNKNOWN` `<<RECEIPT:claim-1>>`.

## 3. Start the pool

The application starts no engine unless you ask. In `config/config.exs`:

```elixir
import Config

config :ash_graphlaw, start_pool: true
```

With `start_pool: true`, `AshGraphLaw.Application` starts `AshGraphLaw.Pool`. Pool size and
timeout come from `config :ash_graphlaw, pool: [size: 4, timeout_ms: 5_000]`. See
[Run the Pool](../how_to/run_the_pool.md) and the [configuration reference](../reference/configuration.md).

## 4. Make the first call

Start `iex -S mix` and run:

```elixir
{:ok, caps} = AshGraphLaw.call(%{"op" => "capabilities"}, [])
caps["abi"]
#=> 1

AshGraphLaw.abi_version()
#=> 1

AshGraphLaw.graphlaw_release()
#=> "v26.9.28"
```

`AshGraphLaw.capabilities/1` wraps the same operation:

```elixir
{:ok, caps} = AshGraphLaw.capabilities([])
caps["abi_version"]
```

`caps["abi_version"]` should equal `AshGraphLaw.abi_version()`. Compare the pinned release with
the manifest the same way:

```elixir
AshGraphLaw.graphlaw_release()
File.read!("priv/graphlaw/MANIFEST.json") |> Jason.decode!() |> Map.fetch!("graphlaw_version")
```

Both values name the same engine release; the first is compiled in from the ontology, the second
is read from the shipped manifest. `AshGraphLaw.call(%{"op" => "capabilities"}, [])` is the raw
form of the same operation.

## 5. Provoke a host refusal

A typed refusal is how the library reports a missing engine. Point one call at a host that does
not exist:

```elixir
{:error, %AshGraphLaw.Refusal{code: code, class: class}} =
  AshGraphLaw.capabilities(server: :no_such_host)

{code, class}
```

The code is `:host_not_started` with class `:blocked_resource`. If you skip step 2 and call the
default pool, the refusal is `:wasm_not_vendored` (class `:blocked_resource`) instead: the
caller never crashes, it receives a value. The closed table is in
[Typed Refusals](../reference/typed_refusals.md).

## Next

Continue with [First Admitted Action](first_admitted_action.md), then build a complete
application in [Admit Your First Resource End to End](admit_your_first_resource_end_to_end.md).

## See Also

- [Vendor the WASM](../how_to/vendor_the_wasm.md)
- [Run the Pool](../how_to/run_the_pool.md)
- [ABI Reference](../reference/abi_reference.md)
- [Typed Refusals](../reference/typed_refusals.md)
- [Troubleshooting](../topics/troubleshooting.md)
