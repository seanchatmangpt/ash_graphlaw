# INDEX — v26.10.28 engine adoption (ash_graphlaw)

Window for the GraphLaw engine adoption v26.9.29 → v26.10.28 in
`/Users/sac/ash_graphlaw` (base HEAD `ff6607807348d26a1ba7b67b756f9ab47f9e6774`).
Receipts live in `RECEIPTS.md` in this dir; receipts embed only command output
that was actually run in this window (compile gate), plus on-disk verification
of every cited-lane claim.

## Tickets

| Id | Title | Status | Conformance target | Current behavior | Required behavior | Acceptance |
|---|---|---|---|---|---|---|
| GL28-ADOPT-1 | Pin bump 26.9.29 → 26.10.28 (3 sites) | PASS | R3 pin parity (HEAD ff66078) | pre-bump: CITATION.cff abstract named v26.9.29; ontology.ttl `glx:graphLawVersion "26.9.29"`; MANIFEST `graphlaw_version 26.9.29` + release URL v26.9.29 | all three surfaces name 26.10.28 consistently; partial single-surface bump must fail the R3 court | verified on disk (see RECEIPTS R-1) |
| GL28-ADOPT-2 | MANIFEST WASI import allowlist 7 → 28 | PASS | `host_abi.imports` vs module type section | pre-bump MANIFEST allowed 7 imports; released v26.10.28 module imports 28 | allowlist enumerates all 28 module imports with exact params/results; zero drift vs ontology `glx:WasiImport` rows | RECEIPTS R-3: count diff + full cross-check, diffs NONE |
| GL28-ADOPT-3 | Vendor + verify ALIVE | PASS | sha256 pin in priv/graphlaw/MANIFEST.json | pre-bump artifact sha 7bb2a7e5… | vendored `priv/graphlaw/graphlaw.wasm` sha256 34fd4ada… matches MANIFEST artifact pin; `abi_version` = 1 | RECEIPTS R-2: shasum on disk matches pin |
| GL28-ADOPT-4 | Digest-rule-aware scripts | PASS | scripts/generate_capability_cards.py digest rule | cards carried no registry digest binding | cards bind `registry_blake3` (b3sum) or `registry_sha256` over canonical JSON; absent digest key is a typed `REFUSED(registry_digest_key_absent)` exit | scripts/generate_capability_cards.py:67–87 (read on disk) |
| GL28-ADOPT-5 | ggen regeneration (28 WasiImport ontology rows); ggen sync re-locked (ggen.toml `[packs]` → `vendor/ggen-marketplace` at pinned marketplace sha, `gates/080`/`gates/090` bind the imported registry block) | PASS | ontology.ttl `glx:WasiImport` == MANIFEST imports | ontology carried 7 WasiImport rows | 28 rows, one per module import, names+params+results identical to MANIFEST | RECEIPTS R-3 cross-check: 28/28, diffs NONE |
| GL28-ADOPT-6 | Compile gate (embedded, run in this window) | PASS | cheapest rung of the test ladder | at 03:38Z `mix compile` exited 1 on BOTH a fresh lane root and the shared `_build` (uncommitted L-wave `capability/` refactor had removed `AshGraphLaw.Dsl.Admission`; pre-existing, not the adoption diff) — the owning lane fixed it within the compile-freeze SLA | exit 0 on shared `_build` AND a fresh lane root | RECEIPTS R-4: real output embedded from the 03:47Z generation run (exit 0) + fresh-root re-verify exit 0 (`Compiling 117 files`, `Generated ash_graphlaw app`); lane lease `_build-lane-docs` deleted after the run |
| GL28-PARITY-6/7/9 | Parity P6/P7/P9 + full `mix test` suite | PENDING | parity register R89 scope | not run in this window | full suite green at adoption HEAD | cited-lane work; file receipts here when run |

## Already-implemented boundary (verified on disk, not re-asked)

- R3 pin-parity court already exists at HEAD ff66078 ("partial pin bump fails
  the court", both single-surface bump mutations falsified) — GL28-ADOPT-1 is a
  data bump under an existing court, not new court work.
- `AshGraphLaw.WasmConfig.import_allowlist/0` already reads `host_abi.imports`
  from the generated manifest (lib/ash_graphlaw/wasm_config.ex:198–205) — the
  28-row allowlist flows through existing code, no API change required.

## Standing vocabulary

PASS = verified on disk this window with embedded command output in RECEIPTS.md.
PENDING = cited-lane work, not executed here. FAIL = real run, real exit code.

## Replay

`RECEIPTS.md` is generated, not hand-written: `python3
docs/jira/v26.10.28/gen_receipts.py` re-executes every receipted command and
rewrites the file from fresh output. The compile gate runs inside that
generation. R-4 also records the historical 03:38Z FAIL (embedded from this
session's live runs, before the owning lane's SLA fix landed).
