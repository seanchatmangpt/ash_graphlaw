# GraphLaw wasm/ABI Lineage Map — MAP-THEN-CLOSE lane E6 (v26.10.2)

Lane: E6 of the MAP-THEN-CLOSE fan-out. Maps the GraphLaw kernel (`~/graphlaw`) to its
consumers (`ash_graphlaw`, `ggen_igniter`, `ash_a2a`) and to the marketplace pack
(`graphlaw-ash-capability-pack`). All shas measured 2026-10-02.

## Identities

| repo | origin | branch | HEAD | version | tags |
|---|---|---|---|---| hosted CI (gh run list, 2026-10-02) |
| graphlaw | seanchatmangpt/graphlaw | `graphlaw-registry-limits` | `5cfe87a` (2026-09-30) | 26.9.29 | `v26.9.29`, `v26.9.28`; releases v26.9.29 (Latest, 2026-10-01), v26.9.28 | CI + Release green on main merge (`36796733697`); earlier workflow_dispatch Release red |
| ash_graphlaw | seanchatmangpt/ash_graphlaw | `main` | `15307b48` (2026-10-02) | committed 26.9.30; working tree carries the uncommitted 26.10.1 bump (mix.exs, CHANGELOG, CITATION, README, ontology.ttl) | NONE (no local, no remote tags) despite the 26.10.1 Hex publish | failing: `Flake Hunt` (schedule) + `CI` red on push `36899459547` (2026-10-01); OpenSSF green |

Branch facts that matter downstream:

- graphlaw `5cfe87a` ("registry: model all resource limits, model shapes, honest wasm pin") is
  1 commit ahead of `main` (`0bb0df2a` = merge release/crates-io-26.9.29) and is **UNPUSHED**
  (`git branch -r --contains 5cfe87a` is empty). It carries: registry `limits` expanded 6 -> 15,
  new `limit_meta` (scope/unit/source), `models` + `model_enums`, and the ARTIFACTS.sha256 wasm
  pin `8bfff66c...`.
- ash_graphlaw CI pin used by xaas (`xaas/.github/workflows/ci_cd.yaml:101`,
  landed in de15fd14) is `03dbb36a` — an ancestor of HEAD, exactly 1 commit behind.

## Wasm artifact lineage (sha256, measured)

| artifact | sha256 (first 8) | bytes | lineage |
|---|---|---|---|
| graphlaw working-tree build `target/wasm32-wasip1/wasm/graphlaw_wasm.wasm` | `8bfff66c` | 6,657,549 | graphlaw-registry-limits (5cfe87a, **unpushed**), Cargo 26.9.29, WASI, ABI 1 |
| graphlaw `target/wasm-abi/.../graphlaw_wasm.wasm` | `743c10ae` | — | same tree, different cargo profile (`wasm-abi`); dev artifact, not a pin |
| graphlaw **v26.9.29 release asset** `graphlaw.wasm` | `7bb2a7e5` | — | published release (tag `0a38b68c`); the frozen v26.9.29 line |
| graphlaw **v26.9.28 release asset** `graphlaw.wasm` | `30f6bc6e` | 6,457,658 | prior release |
| **ash_graphlaw** `priv/graphlaw/graphlaw.wasm` | `7bb2a7e5` | — | byte-exact copy of the v26.9.29 release asset; `priv/graphlaw/MANIFEST.json` pins it by URL + sha, ABI 1 |
| **ggen_igniter** `priv/graphlaw_wasm.wasm` | `8bfff66c` | 6,657,549 | byte-exact copy of the unpushed registry-limits build; pinned in `lib/ggen_igniter/engine/graphlaw.ex` `@wasm_sha256` |
| **ash_a2a** `priv/graphlaw/praxis_graphlaw.wasm` | `187688d9` | 3,249,361 | **praxis-graphlaw v26.7.5** (built 2026-07-08 from praxis `bf96ea56`, wasm32-unknown-unknown, wbindgen string ABI; exports only `blake3_hex`/`graph_hash`/`validate_all`/`run_hooks`) — a different lineage entirely, two generations behind |

## Capability registry lineage (sha256 of capability-registry.json)

| surface | digest (first 8) | contents |
|---|---|---|
| v26.9.29 **release asset** (frozen; schema `graphlaw.capability-registry/1`, ABI 1) | `55d01c81` | 6 limits, no `models`, no `limit_meta` |
| graphlaw working tree `registry/` (5cfe87a, unreleased) | `dcecf65b` | 15 limits + `limit_meta` (scope/unit/source) + `models`/`model_enums` |
| **ash_graphlaw** `priv/graphlaw/capability-registry.json` | `55d01c81` | byte-identical to the v26.9.29 release (`diff` clean) |
| marketplace pack `graphlaw-ash-capability-pack` 26.9.30 | (input, not vendored) | ontology vocabulary includes `gac:Limit` with scope/unit/source and `gac:Model*` — i.e. the **unreleased** registry-limits vocabulary |

## Drift verdicts (the LOOP question: same ABI/registry everywhere?)

1. **ash_graphlaw vs frozen v26.9.29 — ALIGNED.** Wasm bytes and registry bytes are exact
   copies of the published release; MANIFEST pin verifies; generated surface matches the
   released registry (6 limits with empty scope/unit/source, no Model structs — exactly what
   the released registry carries).
2. **ggen_igniter vs released line — ARTIFACT DRIFT (same ABI).** ggen ships `8bfff66c`, which
   is the build of the unpushed 5cfe87a tree, not any published release asset. The commit is
   additive (schema id unchanged, ABI_VERSION stays 1), so no ABI break, but ggen's pin
   currently points at bytes reproducible only from an unpushed local commit. Closure action
   for the coordinator: publish 5cfe87a (merge to main + release, or push the branch), then
   ggen's pin becomes reproducible; optionally re-pin ggen to the new release asset.
3. **ash_a2a vs everything — DRIFTING, two generations, different ABI family.** Its wasm is
   praxis-graphlaw v26.7.5 (July 2026, wbindgen string ABI, 4 semantic exports). The frozen
   registry ABI 1 ops are not reachable through it; its own MANIFEST honestly documents the
   lineage and that rebuild-at-head was BLOCKED at praxis 31f149d. NOT closable by artifact
   copy: the host (`priv/graphlaw/graphlaw_host.mjs` family) speaks the wbindgen string ABI, so
   moving to the graphlaw WASI/`gl_call` ABI is a host-code migration, not a copy.
4. **graphlaw's own ARTIFACTS.sha256 header — internal contradiction.** The comment says the
   "v26.9.29 release, whose graphlaw.wasm digest is b4cf5dd1...", but the actual published
   v26.9.29 asset is `7bb2a7e5` (and v26.9.28 is `30f6bc6e`; neither matches `b4cf5dd1`).
   `git log -S b4cf5dd1` traces the digest to the extraction-era commits (`fd27828`, `984a230`,
   the revert `0a38b68`), i.e. it is the pre-release extraction-time digest that was never
   updated after the release was cut. One-line comment fix owed by the kernel repo owner.
5. **marketplace pack 26.9.30 — AHEAD of the released registry.** Its vocabulary expects
   `limit_meta`/`models` (registry-limits), while its README identifies the source as
   "GraphLaw 26.9.29". Ash-consumers generated from it against the released registry will get
   empty scope/unit/source and no Models (ash_graphlaw's current state) until the
   registry-limits registry is published and consumers regenerate. Forward-compatible, not
   broken; label vs target mismatch is documentation-level.
6. **xaas CI pin `03dbb36a` — STALE BY ONE.** Ancestor of current HEAD; CI qualifies
   HEAD~1, not HEAD. Coordinator action: bump the ref in `xaas/.github/workflows/ci_cd.yaml`.

## Test suites (run 2026-10-02)

- graphlaw (`graphlaw-registry-limits` @ `5cfe87a`): plain `cargo test` FAILS TO COMPILE on the
  default feature set (5 x E0433 `cannot find module or crate common` — `tests/common/mod.rs`
  is `cfg(feature = "abi")`-gated while `tests/op_differential.rs`/`tests/wasm_abi.rs` reference
  it unconditionally; CI itself runs with `--features abi`, so this bites only default-feature
  local runs). `cargo test --features abi`: **391 passed / 0 failed / 0 ignored, all suites
  green**.
- ash_graphlaw (`main` @ `15307b48`, working tree carrying the in-flight 26.10.1 bump):
  `MIX_BUILD_ROOT=_build-e6 mix test` → **66 properties, 975 tests, 1 failure, 7 skipped**
  (149 excluded; ~48s). The one failure is PRE-EXISTING at HEAD, not lane- or tree-introduced:
  `test/unit/parity_test.exs:51` pins `Parity.check_ids() == ~w(P1..P9 R1)` while committed
  `lib/ash_graphlaw/parity.ex:73` already lists `R2` ("live runtime ABI identity equals the
  pinned MANIFEST abi_version"). Fix is one line: add `R2` to the test's expected list.

## Actions taken vs reported

- Taken: wrote this doc (the only write in either repo by lane E6); no code, no artifact
  copies, no commits, no pushes.
- Reported for the coordinator:
  1. graphlaw: merge/push `5cfe87a` and cut a release so `8bfff66c` becomes a published,
     reproducible asset (ggen's pin then resolves against a real ref); fix the
     `b4cf5dd1` claim in `registry/ARTIFACTS.sha256`.
  2. ash_graphlaw: commit the in-flight 26.10.1 release bump and push tag `v26.10.1` (no tags
     exist at all despite the Hex publish).
  3. xaas: bump the CI pin `03dbb36a` -> current HEAD in `ci_cd.yaml`.
  4. ash_a2a: schedule the praxis-wasm -> graphlaw-wasm host migration (code, not copy).
  5. ash_graphlaw CI is red (`CI` + `Flake Hunt`); diagnose before the 26.10.2 epoch work.
     Local suite shows the pre-existing `parity_test.exs` failure (add `R2` to the expected
     id list, one line) — fix forward with the 26.10.2 work.
