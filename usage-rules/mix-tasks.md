<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Mix Tasks

- `mix ash_graphlaw.vendor [--from PATH | --check]`: fetch and digest-check the engine. Downloading
  needs the consent of the person running it; do not run it unprompted. Never commit
  `priv/graphlaw/*.wasm`.
- `mix ash_graphlaw.verify`: admit the vendored engine and compare `abi_version`.
- `mix ash_graphlaw.parity [--evidence-dir DIR] [--list] [--no-examples] [--wasm PATH]`: the
  capability parity court. It never skips; an absent engine is `[wasm_not_vendored]`. Do not add a
  skip flag. `--no-examples` reports P9 as `not_run`, never `pass`.
- `MIX_ENV=test mix ash_graphlaw.mutate [--only ID] [--evidence-dir DIR] [--list] [--require-killed]`.
- `mix ash_graphlaw.install`: generated; `--target` is `UNSUPPORTED`.
- `mix spark.cheat_sheets`: regenerates `documentation/dsls/DSL-AshGraphLaw.Resource.md`.
- Scripts: `scripts/vendor_registry.sh`, `scripts/import_registry.sh`,
  `scripts/vendor_marketplace.sh`, `scripts/ggen_sync.sh`. `--check` variants write nothing (or
  compare two syncs) and exit non-zero on a difference.
- Report the real exit code and output. Do not report a task as passing from its documentation.

See [mix tasks](../documentation/reference/mix_tasks.md).
