# TODO-FIX-AND-FINISH (ash_graphlaw)

Standing: UNVERIFIED

Source: `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R6, re-read where marked confirmed.

## Fix

- HIGH `lib/ash_graphlaw/authority.ex:111-119` claim never verifies lease signature in Elixir
  (confirmed; comment line 53 delegates to engine). Check: forged-lease test passes unskipped.
- HIGH `test/adversarial/lease_ceiling_test.exs:197,220` forged-lease tests carry `@tag skip`
  (confirmed). Check: tags removed once engine pin supports it; `mix test` shows 0 skipped.
- MED `lib/ash_graphlaw/change/admit.ex:284-288` `law.data/2` unrescued, result unvalidated
  (confirmed). Check: raising/junk `data/2` yields typed refusal.
- MED `lib/ash_graphlaw/authority.ex:207,236-237` `check_op` fail-open without lease: UNVERIFIED.
- MED `lib/ash_graphlaw/capability/canonical_json.ex:36-52` `blake3/1` shells to undeclared
  `b3sum` (confirmed; path moved from review). Check: pure-Elixir/declared dep, no System.cmd.
- MED `test/test_helper.exs:44-51` wasm tests silently excluded to stderr (confirmed); scripted
  fake engine at `scripted_engine_helper.exs` UNVERIFIED. Check: CI fails when wasm unavailable.
- MED `Admissible` default-projection fallback on junk (`admissible.ex`), `sa2a_evidence_
  admission.ex:85-100` self-consistency only: UNVERIFIED.
- LOW `Coerce` enum/nullable unenforced; `projection/default.ex` leaks via inspect; undeclared
  Jason; stale README counts / mix.exs comment: UNVERIFIED.

## Finish

- Pin engine to a version that enforces signed leases; unskip adversarial lease tests.
- Replace scripted `admit_all` fake with a real engine path in CI. Check: no fake in test_helper.

## Commit hygiene

- `git status --short` clean at write time (confirmed); nothing pending.

## Decide

- Is Elixir-side signature verification required, or is engine-only authority the contract?

## Reuse

- `capability/coerce.ex:36-188` field-spec coercion; `contract.ex:130-228` refusal vocabulary
  (for ash_surface; see review R6).

## See Also

- `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md`
