<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Getting Started

By the end you will have added `:ash_graphlaw`, vendored the pinned GraphLaw WASM, started the
pool and made one `capabilities` call. Steps that need the engine depend on the vendored file
being present; their output below is what the ABI test in `/Users/sac/graphlaw` asserts
(`abi_version` 1). This tutorial's own run output is UNKNOWN until the test suite exercises it.

## 1. Add the dependency

```elixir
def deps do
  [
    {:ash, "~> 3.33"},
    {:ash_graphlaw, "~> 26.9.29"}
  ]
end
```

```bash
mix deps.get
```

## 2. Vendor the WASM

The engine binary is not shipped in the Hex package. Fetch it and verify its SHA-256 against
`priv/graphlaw/MANIFEST.json`:

```bash
mix ash_graphlaw.vendor
mix ash_graphlaw.vendor --check
```

`--check` writes nothing and exits non-zero when the file is absent or its digest differs from
the pin. See [Vendor the WASM](../how_to/vendor_the_wasm.md).

## 3. Start the pool

The application starts no engine unless you ask. In `config/config.exs`:

```elixir
import Config

config :ash_graphlaw, start_pool: true
```

With `start_pool: true`, `AshGraphLaw.Application` starts `AshGraphLaw.Pool`.
See [Run the Pool](../how_to/run_the_pool.md).

## 4. Make the first call

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
```

## 5. See a host refusal

If the WASM file is missing, calls return a typed refusal instead of crashing the caller:

```elixir
{:error, %AshGraphLaw.Refusal{code: code, class: class}} = AshGraphLaw.capabilities([])
{code, class}
#=> {:wasm_not_vendored, :blocked_resource}
```

## Next

Continue with [First Admitted Action](first_admitted_action.md).

## See Also

- [Vendor the WASM](../how_to/vendor_the_wasm.md)
- [Run the Pool](../how_to/run_the_pool.md)
- [ABI Reference](../reference/abi_reference.md)
- [Typed Refusals](../reference/typed_refusals.md)
