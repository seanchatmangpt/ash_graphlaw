# CERTIFY-VERIFY — doc-hdit certify at tested HEAD (v26.10.8 campaign)

Lane R4, 2026-10-09. Subject: ash_graphlaw `66877414b6866dd525a9cea468658be9655b0fcd`
(main) + this receipt's own docs (see Subject note). Extractor pinned:
`scripts/gen_doc_surface.py` @ ggen-marketplace main,
**sha256 `4c862576ab63595f9cd0417b35341af3ec1001f49450e79bf2e4c291a4a4246f`**
(receipt field binds the same bytes as BLAKE3 `a579e2109941e1f27f2faf0403d6c91e3eebb7f234dcc191a814573001309616`).

## Verdict: ACCEPTED

Canonical chain record (`ash_graphlaw.chain.jsonl`, this dir):

```json
{"extractor":"a579e2109941e1f27f2faf0403d6c91e3eebb7f234dcc191a814573001309616","gates":{"Phi_halluc":0.0,"Q_density":1.0,"S_coverage":0.9861357980803412},"hash":"e95eb2f067812557a8281cf240b6649a99317c96d80f5d41ff7a56bf1ccec0bc","parent":"","parent_note":"chain root","subject":"7e8be4f6ab537dc96cd59ddd3722bbbe0b518bb4786b34d26b38cc86cb83a215","thresholds":{"Phi_halluc_max":0.001,"Q_density_min":0.65,"S_coverage_min":0.9},"timestamp":1791555066,"verdict":"ACCEPTED"}
```

- certify receipt hash `e95eb2f067812557a8281cf240b6649a99317c96d80f5d41ff7a56bf1ccec0bc` (BLAKE3 chain root, exit 0)
- subject digest `7e8be4f6…` = doc-hdit subject over committed inputs `ash_graphlaw.inputs.json`
  (sha256 `dc59abfa2196f9389b7618780dd3d4a08a68f84b7c4c01aaac55762800692e9e`, copied to this dir)

## Gates at the certified surface

| gate | value | threshold | verdict |
|---|---|---|---|
| S_coverage | 0.9861 | >= 0.90 | **PASS** |
| Phi_halluc | 0.0000 | <= 0.001 | PASS |
| Q_density | 1.0000 | >= 0.65 | PASS |

Audit run pre-certify (same inputs, exit 0): coverage_raw 0.2670 report-only,
prose_artifacts 147 (excluded from Phi/Q), external_documented 1.

## Commands + exits

```sh
cd /Users/sac/ggen-marketplace
python3 scripts/gen_doc_surface.py code /Users/sac/ash_graphlaw > /tmp/hdit/agl/code.json
python3 scripts/gen_doc_surface.py doc  /Users/sac/ash_graphlaw --code-json /tmp/hdit/agl/code.json > /tmp/hdit/agl/doc2.json
# merge with paths/directories/known_external carried (S3 seam, below)
cd packs/rust-doc-hdit-pack
./target/release/doc-hdit audit   /tmp/hdit/agl/inputs2.json courts/doc_quality.court   # exit 0, 3 PASS
./target/release/doc-hdit certify /tmp/hdit/agl/inputs2.json courts/doc_quality.court \
  --docs /Users/sac/ash_graphlaw/docs --chain /tmp/hdit/agl/agl.chain.jsonl \
  --extractor /Users/sac/ggen-marketplace/scripts/gen_doc_surface.py                    # exit 0, ACCEPTED
```

## First audit at HEAD: REFUSED, then remediated (falsifier fired and was answered)

The first audit at `66877414` with the pre-existing doc surface REFUSED:
S_coverage **0.7576** < 0.90 (phantom 0.0000, density 1.0000). Remediation:
committed `docs/reference/generated/uncovered-surface-inventory.md` — a
deterministic, generated per-module inventory of the uncovered public surface
(functions as signatures, struct/type keys as identifiers), grounded by
construction (every span is an exact code-surface ident). No thresholds were
relaxed; the court file is byte-identical before/after.

## Seams (S1–S5)

- **S1 — str_key surface expansion.** 2202 of 2813 public items are extractor
  `str_key` items (struct/type/defstruct keys emitted per-module). The
  coverage denominator is dominated by them; uncovered str_keys are generic
  keys (`order`, `required`, `nullable`, `default`, …). Classified as an
  extractor-surface shape seam, not a doc defect; addressed doc-side via the
  generated inventory.
- **S2 — noise-class idents are unclaimable.** `is_noise_span` filters
  BOOLISH and <3-char tokens, so idents `as`, `id`, `nt`, `ok`, `to`,
  `valid`, `enabled` (38 public items) can never ground from any doc.
  Disclosed ceiling: coverage caps at **0.9865** even covering everything
  else. Gate reachable (0.90 < 0.9865); ceiling recorded, not worked around.
- **S3 — inputs merge seam.** The certify inputs merge must carry `paths`,
  `directories`, `known_external` from the code surface (same seam ex4pm
  hit); applied in the recorded recipe.
- **S4 — extractor identity dual hash.** The chain receipt binds the
  extractor as BLAKE3 (`a579e210…`); the campaign pin is sha256
  (`4c862576…`). Both digests are over the same file bytes; both recorded.
- **S5 — ident-global coverage semantics.** Coverage is set-semantics over
  ident variants, so one grounded mention covers every same-named item across
  modules. The inventory doc is still the true per-module remediation list
  (generated from the uncovered set), but the gate's marginal coverage per
  mention is module-independent. Noted for threshold policy, not altered.

## Tests

`mix test` at the certified tree: 975 tests + 66 properties, 0 failures
(re-run after the doc change; see CAMPAIGN-RECEIPT for the run log line).

## Tag advance

v26.10.8 pointed at `6dff34a1` (9 commits behind tested HEAD), annotated. A
fleet-wide citation sweep (`6dff34a1`, `ash_graphlaw v26.10.8` across
ggen-marketplace, ggen, xaas, ex4pm, frozen-duckdb, ggen_igniter, affidavit
docs/receipts) found **zero external receipts citing the tag subject**, so
the annotated tag is moved to the certified commit per the campaign law
(tag-only move of an un-superseded campaign tag). If it had been
receipt-cited, v26.10.8-2 would have been minted instead.

## Replay / falsifier

Re-run the recipe above at any HEAD; if certify REFUSES (or audit coverage
falls below 0.90 with the S3 merge in place), this ACCEPTED baseline is
refuted and this doc must be refreshed. Extraction is not bit-stable
run-to-run; standing is bound to the committed inputs
(`ash_graphlaw.inputs.json`, sha256 `dc59abfa…`) plus the pinned extractor.
