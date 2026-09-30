<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Mutation

- The catalog (`AshGraphLaw.Mutation.Catalog`) is an anti-vacuity court: each mutant breaks one
  behavior and a test must fail. A surviving mutant means a vacuous test.
- Run with `MIX_ENV=test mix ash_graphlaw.mutate --require-killed`. Verdicts include
  `mutant_killed`; `--list` prints the catalog.
- The runner compiles only files under `test/` (no symlinks) and refuses a file that redefines a
  module loaded from outside `test/`.
- Killers tagged `:wasm` need the engine; without it those mutants are excluded and the report says
  so. An excluded mutant is not a kill.
- When you add a behavior with a guard (a refusal, a comparison, a digest check), add or extend a
  mutant that removes the guard, and a test that kills it. Parity comparisons expose
  `Parity.same_list?/2` and `same_digest?/2` for this purpose.
- Do not edit test files to make a mutant pass. Fix the test's assertion.

See [run the mutation catalog](../documentation/how_to/run_the_mutation_catalog.md).
