<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# run_the_mutation_catalog

Prove that the negative and adversarial tests are not vacuous: remove each guard that carries the
admission boundary, one at a time, and require a test to fail.

## 1. Run the whole catalog

```bash
MIX_ENV=test mix ash_graphlaw.mutate --evidence-dir tmp/mutation --require-killed
```

Each catalog entry (`AshGraphLaw.Mutation.Catalog`, ids `AGL-MUT-001` upward) names one
`Module.function/arity` and one operator. The task hot-loads that mutant, runs the killer files
(`test/negative/**/*_test.exs`, `test/adversarial/**/*_test.exs`) in the same VM, restores the
original BEAM and verifies the restore by md5, then prints one verdict per entry and writes
`tmp/mutation/mutation_report.json` (canonical, sorted-key JSON).

| Verdict | Meaning |
|---|---|
| `mutant_killed` | a killer test failed under the mutant after the baseline was green: the guard is defended |
| `mutant_survived` | every killer stayed green with the guard removed: the tests are vacuous for that guard |
| `blocked` | the target does not resolve, or no killer file exists (typed code in the report) |
| `unknown` | the baseline was not green, a run could not be read, or the BEAM could not be verifiably restored; never a pass |

`--require-killed` exits non-zero unless every selected verdict is `mutant_killed`.

## 2. Look before you run

```bash
MIX_ENV=test mix ash_graphlaw.mutate --list
MIX_ENV=test mix ash_graphlaw.mutate --only AGL-MUT-004 --only AGL-MUT-014
```

`--list` loads nothing; it prints `id`, target, `resolvable | BLOCKED code` and the number of killer
files. A renamed function shows up as `BLOCKED mutation_function_not_found`; nothing is skipped
silently.

## 3. What a survivor means

A surviving mutant is a finding about the tests, not the library. Write the missing negative test
(with its positive control), rerun that id, and confirm `mutant_killed`. Two examples from this
repository: `AGL-MUT-010` (a host UTF-8 guard) survived because the request codec rejected invalid
UTF-8 before the guard could ever see it, so the refusal moved into `AshGraphLaw.ABI` and the entry
now targets `AshGraphLaw.ABI.classify_encode_error/1`; `AGL-MUT-006` (redaction of sensitive
arguments) survived until a resource with a sensitive action argument was added to the tests.

## 4. Add a mutation

Append an entry to `AshGraphLaw.Mutation.Catalog.entries/0` with the next id. Ids are append-only
and never reused; retarget an entry to a moved function rather than deleting it.

## 5. Containment

The runner compiles killer files with `Code.compile_file/1`, so it admits a file only when it is a
real (non-symlink) path under `test/` and defines no module already loaded from outside `test/`.
Either refusal is returned before anything is compiled.

`:wasm`-tagged killers are excluded, with a printed stderr line, when no engine is vendored; a
guard defended only by a `:wasm` test then reports `mutant_survived`, never a false kill.

## See Also

- [Mix tasks reference](../reference/mix_tasks.md)
- [Claims and evidence](../reference/claims_and_evidence.md)
- [Vendor the WASM](vendor_the_wasm.md)
