<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Install with Igniter

Add `ash_graphlaw` to a project with the generated installer.

## Steps

```bash
mix igniter.install ash_graphlaw
mix deps.get
mix ash_graphlaw.vendor
mix ash_graphlaw.verify
```

`Mix.Tasks.AshGraphlaw.Install` is generated from `ash-extension-pack`. It adds the `wasmex`
dependency and the `AshGraphLaw.Formatter` plugin to `.formatter.exs`. It does not download the
engine: `mix ash_graphlaw.vendor` does that, and only after you run it.

## Attach the extension to a resource

The `--target Module` option is meant to patch a resource. In the pinned pack version it raises a
`SyntaxError` (`UNSUPPORTED(generator-capability)`, see the [support matrix](../reference/support_matrix.md)).
Add the extension by hand:

```elixir
use Ash.Resource,
  domain: MyApp.Domain,
  extensions: [AshGraphLaw.Resource]
```

## Check

`mix ash_graphlaw.verify` admits the vendored engine and compares its `abi_version` with the
manifest. A pass is an observation about those bytes and grants nothing.

## See Also

- [Vendor the WASM](vendor_the_wasm.md)
- [Run the Pool](run_the_pool.md)
- [Mix tasks](../reference/mix_tasks.md)
