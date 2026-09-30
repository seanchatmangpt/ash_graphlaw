<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Ontology First

- `ontology.ttl` (with its `GENERATED-REGISTRY` block), `queries/`, `templates/`, `gates/`,
  `ggen.toml` and the vendored packs are sources. Everything listed by
  `scripts/ggen_sync.sh --list-projections` is a projection: do not edit it.
- Change flow: edit the source, `scripts/vendor_registry.sh`, `scripts/import_registry.sh`,
  `scripts/vendor_marketplace.sh` when the marketplace sha moves, `scripts/ggen_sync.sh`, then
  `scripts/ggen_sync.sh --check`.
- The typed capability surface is generated from the GraphLaw registry through
  `graphlaw-ash-capability-pack`. Never add a per-op module by hand and never edit the
  `GENERATED-REGISTRY` block.
- Handwritten residue starts with `# UNSUPPORTED(generator-capability): <reason>`, has a
  `glx:UnsupportedResidue` row in `ontology.ttl` and a row in `HANDWRITTEN.md`
  (`scripts/ggen_sync.sh --check-ledger`).
- Every template's inline SPARQL is a verbatim copy of its `queries/*.rq`
  (`test/unit/template_query_sync_test.exs`).
- Expose, do not reimplement: no RDF, SPARQL, SHACL, ShEx, N3, Datalog, entailment or planning
  logic in this repository.

See [regenerate with ggen](../documentation/how_to/regenerate_with_ggen.md).
