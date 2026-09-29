<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Testing

## Chicago style

- Use real collaborators: real Ash resources with `Ash.DataLayer.Ets`, the real pinned WASM,
  real Host and Pool processes. Assert on final state, not call counts.
- Do not use Mox, Mimic, meck, `patch`, or any mock. A hand-written real implementation of
  a behaviour is not a mock.
- Run a positive control (baseline admitted or green) before every negative assertion, so a
  refusal proves the input caused it.

## The `:wasm` tag

- Tests needing the real engine are tagged `:wasm` (and `:slow` where costly).
- `test/test_helper.exs` (generated) excludes `:wasm` when `priv/graphlaw/graphlaw.wasm` is
  absent or fails the pin, and prints
  `[wasm] EXCLUDING ... -- reason` to stderr. An exclusion is a visible degraded run, not a
  pass. CI always vendors, so `:wasm` always runs there.
- Do not stub the engine to make excluded tests run.

## Support modules

`test/support/**` owns `AshGraphLaw.Test.Case`, `.Domain`, `.Ticket`, `.ShapeLaw`,
`.PlanLaw`. Use them; do not redefine them.

## Expectations come from the engine

Take law step formats and refusal shapes from `/Users/sac/graphlaw/tests/wasm_abi.rs` and
`docs/refusals.md`, not from memory.

## Layout and ladder

`test/` holds unit, ash, negative, adversarial, integration (`:wasm`), mutation, and
`mix/tasks` tests. Run with `MIX_BUILD_ROOT` set per lane; never share `_build`.

## Mutation

`mix ash_graphlaw.mutate --require-killed` applies mutants (ids `AGL-MUT-NNN`, append-only)
after a green baseline. Verdicts: `mutant_killed`, `mutant_survived`, `blocked`, `unknown`.
The original BEAM is restored and md5-verified. Never mutate `AshGraphLaw.Mutation*`.
Killers live in `test/negative` and `test/adversarial`.

## Claims

`documentation/reference/claims_and_evidence.md` lists each claim with its test file and
standing. Do not state behavior in docs that no test or run demonstrates.

## See Also

[wasm-host.md](wasm-host.md) - [refusals.md](refusals.md) - [../usage-rules.md](../usage-rules.md)
