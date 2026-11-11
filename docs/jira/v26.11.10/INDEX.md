# INDEX — v26.11.10 engine adoption (ash_graphlaw)

Window for the GraphLaw engine adoption v26.10.28 → v26.11.10 in
`/Users/sac/ash_graphlaw`.
Receipts live in `RECEIPTS.md` in this directory; receipts embed only command output
that was actually run in this window (compiler, test ladder, parity court, packaging),
plus on-disk verification of all artifact digests and file states.

## Tickets

| Id | Title | Status | Conformance target | Current behavior | Required behavior | Acceptance |
|---|---|---|---|---|---|---|
| GL1110-ADOPT-1 | Engine & Package Pin Bump to 26.11.10 | PASS | R3 pin parity & SPARQL gate 070 | pre-bump: package 26.10.8, engine v26.10.28 in `ontology.ttl`, `mix.exs`, `MANIFEST.json`, `README.md`, `CITATION.cff`, `engineering-standards.json` | all surfaces name 26.11.10 consistently; gate 070 and R3 court pass without drift | Verified on disk and by `scripts/ggen_sync.sh --check-versions` (RECEIPTS R-1) |
| GL1110-ADOPT-2 | Artifact Pin & Vendoring (GL28-13 Relink) | PASS | sha256 pin in priv/graphlaw/MANIFEST.json | pre-bump artifact 74,097,211 B sha256 `34fd4ada…` | vendored `priv/graphlaw/graphlaw.wasm` 62,909,537 B sha256 `62cd95d4ef7294dcd5976a2f685b71580bb834816e9f4bba0d13d5555e35c8f8` matches MANIFEST artifact pin; `abi_version` = 1 | RECEIPTS R-2: `mix ash_graphlaw.vendor --check` and `mix ash_graphlaw.verify` pass |
| GL1110-ADOPT-3 | Ggen Projections Synchronization | PASS | `scripts/ggen_sync.sh` determinism & ledger | projections had older pins and timestamps | projections regenerated clean; foreign reference packages pruned; ledger 47 residue paths ok | `bash scripts/ggen_sync.sh` exit 0; `--check-ledger` ok (RECEIPTS R-3) |
| GL1110-ADOPT-4 | Test & Documentation Literal Pin Alignment | PASS | Literal assertions in unit/integration suites | test files pinned `34fd4ada…` and `26.10.28` | updated `wasm_config_test.exs`, `engine_load_test.exs`, `pinned_engine_test.exs`, `root_api_test.exs`, `parity_test.exs`, `AGENTS.md`, `REPRODUCE.md`, `CHANGELOG.md` | All literal pin unit and integration tests pass (RECEIPTS R-4) |
| GL1110-ADOPT-5 | Host & Authority Lease Verification Alignment | PASS | `AshGraphLaw.Authority` documentation and ceilings | stale comments stated engine ignores leases | aligned comments with engine signed lease verification in `op_law` and step ceilings | Verified on disk in `lib/ash_graphlaw/authority.ex` and compile gate passes (RECEIPTS R-5) |
| GL1110-ADOPT-6 | Jira Documentation & Live Receipt Generation | PASS | Chatman Equation $R = \{\text{identity}, \text{authority}, \text{consequence}, \text{replay}, \text{standing}\}$ | absent v26.11.10 jira directory | `INDEX.md`, `RECEIPTS.md`, and executable `gen_receipts.py` generated from live executions | `python3 docs/jira/v26.11.10/gen_receipts.py` enforces rc == 0 assertions and produces clean receipts (RECEIPTS R-1 through R-9) |
| GL1110-ADOPT-7 | Full Verification Ladder & Capability Parity | PASS | Zero-warning compile, parity court PARTIAL_ALIVE, full test suite | unverified on new artifact | `mix compile --warnings-as-errors` exit 0 (R-5); `mix test` passes all 1,055 tests (R-6); `mix ash_graphlaw.parity` passes all 12 checks (R-7) | RECEIPTS R-5, R-6 & R-7 |
| GL1110-ADOPT-8 | Hex Packaging & Publication | PASS | `mix hex.build` & `mix hex.publish` | unbuilt 26.11.10 package | package archive built cleanly; publish executed with authenticated hex session | `ash_graphlaw-26.11.10.tar` generated (R-8) and dry-run published (RECEIPTS R-8 & R-9) |
| GL1110-PANEL-1 | 10-Persona Code & Docs Improvements | PASS | Expert architecture standards across 10 disciplines | Individual domain improvements scattered | 10 personas (Zach Daniel, Joe Armstrong, José Valim, Chris McCord, Pragmatic Programmers, Robert Virding, Saša Jurić, Andrea Leopardi, Wojtek Mach, Typed Systems Expert) review and improve codebase | Clean compile, 0 warnings, verified against domain invariants (RECEIPTS R-10a, R-10b, R-11, R-12) |
| GL1110-PANEL-2 | 10-Persona Review Panel Documentation | PASS | Panel audit in `docs/` and `CHANGELOG.md` | Undocumented persona contributions | Complete review log in `docs/PERSONA_REVIEW_PANEL.md` and detailed release notes in `CHANGELOG.md` | File exists on disk, non-empty, linked in docs (RECEIPTS R-10a, R-10b) |
| GL1110-PANEL-3 | Extended Jira Panel Receipts & Generation | PASS | Enforced rc == 0 across all release and panel gates | `gen_receipts.py` covered only ADOPT-1..8 | `gen_receipts.py` includes panel gate validations, dialyzer check, and executes status 0 | `python3 docs/jira/v26.11.10/gen_receipts.py` exits 0 (RECEIPTS R-1..R-12) |
| GL1110-PANEL-4 | Hex Packaging & Publication Hygiene | PASS | Hex release archive & publication dry-run | Archive built but doc links had warnings | `ash_graphlaw-26.11.10.tar` (273KB) verified; Hex authentication active; dry-run publish clean | `mix hex.build` exit 0; `mix hex.publish --yes --dry-run` exit 0 (RECEIPTS R-8, R-9, R-12) |
| GL1110-PANEL-5 | Full Verification Ladder with Zero Regressions | PASS | Complete CI/verification ladder pass | Multi-agent concurrency verified | Compiler, Dialyzer (0 errors), full test suite (1,055 tests), parity court (12/12 checks) pass | `mix compile --warnings-as-errors`, `mix dialyzer`, `mix test`, `mix ash_graphlaw.parity` exit 0 (RECEIPTS R-5, R-6, R-7, R-11) |

## Already-implemented boundary (verified on disk)

- The 28 WASI Preview 1 imports (`wasi_snapshot_preview1`) and 4 ABI exports (`gl_alloc`, `gl_call`, `gl_free`, `memory`) remain invariant across ABI version 1.
- The capability registry (14 ops) in `priv/graphlaw/capability-registry.json` is byte-identical (`registry_blake3` `blake3:6e1103673508ade20f2276e93c7c948dd4f7c31689a25a325fac4a308856035d`, `surface_blake3` `blake3:da96e1375a76610b5d91aedb9b01d5ac0807b0f850ce4440628c37a3b96b9ee9`).
- Initial WebAssembly linear memory allocation drops from 322 pages to 74 pages (-15.37 MiB) due to the ICU-root-removal relink (GL28-13).

## Standing vocabulary

- **PASS**: Verified on disk in this execution window with embedded real command output in `RECEIPTS.md`.
- **PARTIAL_ALIVE**: Parity court observed execution against the exact vendored engine subject (`mix ash_graphlaw.parity`).
- **ALIVE**: Admitted subject with observed execution and consequence.
- **BLOCKED**: Blocked by missing external resource.
- **FAIL**: Real run with non-zero exit code.

## Replay

`RECEIPTS.md` is generated programmatically: `python3 docs/jira/v26.11.10/gen_receipts.py` executes subprocess commands, hashes artifacts, captures stdout/stderr, and renders `RECEIPTS.md` following the Chatman Equation.
