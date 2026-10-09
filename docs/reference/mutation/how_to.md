# How to: Using ash_graphlaw

## Prerequisites


- AshGraphLaw.Mutation.Catalog::entries (function)

- AshGraphLaw.Mutation.Catalog::fetch (function)

- AshGraphLaw.Mutation.Catalog::ids (function)

- AshGraphLaw.Mutation.Catalog::killers (function)

- AshGraphLaw.Mutation.Catalog::resolution (function)

- AshGraphLaw.Mutation.Collector::drop_table (function)

- AshGraphLaw.Mutation.Collector::failed (function)

- AshGraphLaw.Mutation.Collector::handle_cast (function)

- AshGraphLaw.Mutation.Collector::init (function)

- AshGraphLaw.Mutation.Collector::new_table (function)

- AshGraphLaw.Mutation.Runner::admit_files (function)

- AshGraphLaw.Mutation.Runner::default_exclusions (function)

- AshGraphLaw.Mutation.Runner::run (function)

- AshGraphLaw.Mutation.Runner::summary (type)

- AshGraphLaw.Mutation.Verdict::AshGraphLaw.Mutation.Verdict (struct)

- AshGraphLaw.Mutation.Verdict::canonical_json (function)

- AshGraphLaw.Mutation.Verdict::t (type)

- AshGraphLaw.Mutation.Verdict::tally (function)

- AshGraphLaw.Mutation.Verdict::to_map (function)

- AshGraphLaw.Mutation.Verdict::verdict (type)

- AshGraphLaw.Mutation.Verdict::verdicts (function)

- AshGraphLaw.Mutation::AshGraphLaw.Mutation (struct)

- AshGraphLaw.Mutation::baseline (function)

- AshGraphLaw.Mutation::mutate_forms (function)

- AshGraphLaw.Mutation::operator (type)

- AshGraphLaw.Mutation::plan (type)

- AshGraphLaw.Mutation::prepare (function)

- AshGraphLaw.Mutation::pristine? (function)

- AshGraphLaw.Mutation::protected? (function)

- AshGraphLaw.Mutation::qualify (function)

- AshGraphLaw.Mutation::refusal (type)

- AshGraphLaw.Mutation::refusal_codes (function)

- AshGraphLaw.Mutation::resolve_killers (function)

- AshGraphLaw.Mutation::restore! (function)

- AshGraphLaw.Mutation::selector (type)

- AshGraphLaw.Mutation::t (type)

- AshGraphLaw.Mutation::target (function)

- AshGraphLaw.Mutation::with_mutant (function)


## Steps


1. Use `baseline` from `AshGraphLaw.Mutation`.

2. Use `mutate_forms` from `AshGraphLaw.Mutation`.

3. Use `prepare` from `AshGraphLaw.Mutation`.

4. Use `pristine?` from `AshGraphLaw.Mutation`.

5. Use `protected?` from `AshGraphLaw.Mutation`.

6. Use `qualify` from `AshGraphLaw.Mutation`.

7. Use `refusal_codes` from `AshGraphLaw.Mutation`.

8. Use `resolve_killers` from `AshGraphLaw.Mutation`.

9. Use `restore!` from `AshGraphLaw.Mutation`.

10. Use `target` from `AshGraphLaw.Mutation`.

11. Use `with_mutant` from `AshGraphLaw.Mutation`.

12. Use `AshGraphLaw.Mutation` from `AshGraphLaw.Mutation`.


## Verified snippet

<!-- The snippet slot carries code copied from the extracted code surface -->
<!-- (doc:Claim rows whose doc:attribute is "snippet"), never agent prose. -->

```rust
// AshGraphLaw.Mutation :: baseline
baseline/2
```

<!-- AGENT-COMMENTARY-BEGIN -->
<!-- The ONLY region an agent may write into. Bounds: <= 12 lines,    -->
<!-- <= 100 chars/line, no new code facts (any new symbol mentioned   -->
<!-- must exist in queries/ast_extract.rq output; the doc_quality     -->
<!-- court fails Phi_halluc > 0.001 otherwise). No tables, no         -->
<!-- signatures, no parameters, no error lists — AGENT-FORBIDDEN      -->
<!-- everywhere.                                                      -->
<!-- AGENT-COMMENTARY-END -->
