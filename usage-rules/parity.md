<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Parity

- Parity is a failing court: the typed AshGraphLaw capability set must equal the set the engine
  reports. Run `mix ash_graphlaw.parity` and report the output.
- Never add a skip, an allow-list of drifted ops, or a check that cannot fail. The court raises
  `[capability_parity_drift] <ids>` and `[wasm_not_vendored]`.
- Check ids are frozen: `P1` to `P9` and `R1`. Do not hardcode the op count; compare with the
  registry.
- Engine pin `v26.9.28` predates the registry. Against it, drift is reported and stays reported
  until the pin moves to a release asset that carries the registry. Do not mask it.
- When the registry changes: `scripts/vendor_registry.sh`, `scripts/import_registry.sh`,
  `scripts/ggen_sync.sh`, then the court.
- A pass is `PARTIAL_ALIVE` for that engine and registry. It is not `ALIVE` without an exact-SHA
  receipt.

See [run the parity court](../documentation/how_to/run_the_parity_court.md).
