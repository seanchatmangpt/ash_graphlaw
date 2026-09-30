<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Run the Parity Court

Check that the typed AshGraphLaw surface equals the surface the engine reports.

## Run

```bash
mix ash_graphlaw.vendor        # the court never skips: no engine is a refusal
mix ash_graphlaw.parity --evidence-dir tmp/evidence
mix ash_graphlaw.parity --list # print check ids and titles, load no engine
```

Options: `--evidence-dir DIR`, `--list`, `--no-examples` (P9 is then `not_run`, never `pass`),
`--wasm PATH` (unpinned engine bytes). Full reference: [mix tasks](../reference/mix_tasks.md).

## Read the output

Each line is `id`, `status`, `title` for `P1` to `P9` and `R1`. Exit 0 means no check drifted. A
failure raises `[capability_parity_drift] <check ids>`; a missing engine raises
`[wasm_not_vendored] ...`. With `--evidence-dir`, `parity_report.json` (canonical JSON) is written
in both cases.

## Expected failure against the v26.9.28 pin

The engine pin is `v26.9.28`; the registry is `v26.9.29`. The `capabilities` response of the
pinned engine has no `registry_sha256`, so `P3` reports that field `UNKNOWN`. Whether other checks
drift against that engine is UNKNOWN until the court is run. A drift is reported, never masked; the
fix is the pin bump to the release that carries the registry.

## Standing

A pass is `PARTIAL_ALIVE` for that engine and registry. It is not `ALIVE` without an exact-SHA
receipt.

## From Elixir

```elixir
case AshGraphLaw.Parity.run(examples: true) do
  {:ok, report} -> report["checks"]
  {:error, %{refusal: refusal, report: report}} -> {refusal.code, report["checks"]}
end
```

## See Also

- [Capability registry and parity](../topics/capability_registry_and_parity.md)
- [Usage rule: parity](../../usage-rules/parity.md)
- [Support matrix](../reference/support_matrix.md)
