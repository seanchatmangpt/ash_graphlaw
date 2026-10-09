# ash_graphlaw reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### AshGraphLaw.Mutation

| `baseline` | function | baseline/2 |  |  |  |  |

| `mutate_forms` | function | mutate_forms/2 |  |  |  |  |

| `prepare` | function | prepare/2 |  |  |  |  |

| `pristine?` | function | pristine?/1 |  |  |  |  |

| `protected?` | function | protected?/1 |  |  |  |  |

| `qualify` | function | qualify/2 |  |  |  |  |

| `refusal_codes` | function | refusal_codes/0 |  |  |  |  |

| `resolve_killers` | function | resolve_killers/2 |  |  |  |  |

| `restore!` | function | restore!/1 |  |  |  |  |

| `target` | function | target/1 |  |  |  |  |

| `with_mutant` | function | with_mutant/3 |  |  |  |  |

| `AshGraphLaw.Mutation` | struct | defstruct id, module, function, arity, operator, guard, description, clauses: :all, killers: [] |  |  |  |  |

| `operator` | type | @type operator :: {:replace_body, String.t()} | {:negate_guard} |  |  |  |  |

| `plan` | type | @type plan :: %{ mutation_id: String.t(), module: module(), function: atom(), arity: non_neg_integer(), target: String.t(), filename: charlist(), original_binary: binary(), original_md5: String.t(), mutant_binary: binary(), mutant_md5: String.t(), clauses_mutated: pos_integer() } |  |  |  |  |

| `refusal` | type | @type refusal :: %{code: atom(), detail: String.t()} |  |  |  |  |

| `selector` | type | @type selector :: :all | {:clause, pos_integer()} |  |  |  |  |

| t | type | @type t :: %__MODULE__{ id: String.t(), module: module(), function: atom(), arity: non_neg_integer(), operator: operator(), clauses: selector(), guard: String.t() | nil, description: String.t() | nil, killers: [String.t()] } |  |  |  |  |


### AshGraphLaw.Mutation.Catalog

| `entries` | function | entries/0 |  |  |  |  |

| `fetch` | function | fetch/1 |  |  |  |  |

| `ids` | function | ids/0 |  |  |  |  |

| `killers` | function | killers/0 |  |  |  |  |

| `resolution` | function | resolution/1 |  |  |  |  |


### AshGraphLaw.Mutation.Collector

| `drop_table` | function | drop_table/0 |  |  |  |  |

| `failed` | function | failed/0 |  |  |  |  |

| `handle_cast` | function | handle_cast/2 |  |  |  |  |

| `init` | function | init/1 |  |  |  |  |

| `new_table` | function | new_table/0 |  |  |  |  |


### AshGraphLaw.Mutation.Runner

| `admit_files` | function | admit_files/2 |  |  |  |  |

| `default_exclusions` | function | default_exclusions/0 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `summary` | type | @type summary :: %{ total: non_neg_integer(), failures: non_neg_integer(), skipped: non_neg_integer(), excluded: non_neg_integer(), failed: [String.t()] } |  |  |  |  |


### AshGraphLaw.Mutation.Verdict

| `canonical_json` | function | canonical_json/1 |  |  |  |  |

| `tally` | function | tally/1 |  |  |  |  |

| `to_map` | function | to_map/1 |  |  |  |  |

| `verdicts` | function | verdicts/0 |  |  |  |  |

| `AshGraphLaw.Mutation.Verdict` | struct | defstruct mutation_id, target, verdict, code, detail, mutant_calls, applied, restored, baseline, mutant, killers: [], killer_files: [], missing_killers: [], killed_by: [] |  |  |  |  |

| t | type | @type t :: %__MODULE__{ mutation_id: String.t(), target: String.t(), verdict: verdict(), code: atom() | nil, detail: String.t() | nil, mutant_calls: non_neg_integer() | nil, applied: map() | nil, restored: map() | nil, baseline: map() | nil, mutant: map() | nil, killers: [String.t()], killer_files: [String.t()], missing_killers: [String.t()], killed_by: [String.t()] } |  |  |  |  |

| `verdict` | type | @type verdict :: :mutant_killed | :mutant_survived | :blocked | :unknown |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `baseline` | function | baseline/2 |  |  |  |  |

| `mutate_forms` | function | mutate_forms/2 |  |  |  |  |

| `prepare` | function | prepare/2 |  |  |  |  |

| `pristine?` | function | pristine?/1 |  |  |  |  |

| `protected?` | function | protected?/1 |  |  |  |  |

| `qualify` | function | qualify/2 |  |  |  |  |

| `refusal_codes` | function | refusal_codes/0 |  |  |  |  |

| `resolve_killers` | function | resolve_killers/2 |  |  |  |  |

| `restore!` | function | restore!/1 |  |  |  |  |

| `target` | function | target/1 |  |  |  |  |

| `with_mutant` | function | with_mutant/3 |  |  |  |  |

| `AshGraphLaw.Mutation` | struct | defstruct id, module, function, arity, operator, guard, description, clauses: :all, killers: [] |  |  |  |  |

| `operator` | type | @type operator :: {:replace_body, String.t()} | {:negate_guard} |  |  |  |  |

| `plan` | type | @type plan :: %{ mutation_id: String.t(), module: module(), function: atom(), arity: non_neg_integer(), target: String.t(), filename: charlist(), original_binary: binary(), original_md5: String.t(), mutant_binary: binary(), mutant_md5: String.t(), clauses_mutated: pos_integer() } |  |  |  |  |

| `refusal` | type | @type refusal :: %{code: atom(), detail: String.t()} |  |  |  |  |

| `selector` | type | @type selector :: :all | {:clause, pos_integer()} |  |  |  |  |

| t | type | @type t :: %__MODULE__{ id: String.t(), module: module(), function: atom(), arity: non_neg_integer(), operator: operator(), clauses: selector(), guard: String.t() | nil, description: String.t() | nil, killers: [String.t()] } |  |  |  |  |

| `entries` | function | entries/0 |  |  |  |  |

| `fetch` | function | fetch/1 |  |  |  |  |

| `ids` | function | ids/0 |  |  |  |  |

| `killers` | function | killers/0 |  |  |  |  |

| `resolution` | function | resolution/1 |  |  |  |  |

| `drop_table` | function | drop_table/0 |  |  |  |  |

| `failed` | function | failed/0 |  |  |  |  |

| `handle_cast` | function | handle_cast/2 |  |  |  |  |

| `init` | function | init/1 |  |  |  |  |

| `new_table` | function | new_table/0 |  |  |  |  |

| `admit_files` | function | admit_files/2 |  |  |  |  |

| `default_exclusions` | function | default_exclusions/0 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `summary` | type | @type summary :: %{ total: non_neg_integer(), failures: non_neg_integer(), skipped: non_neg_integer(), excluded: non_neg_integer(), failed: [String.t()] } |  |  |  |  |

| `canonical_json` | function | canonical_json/1 |  |  |  |  |

| `tally` | function | tally/1 |  |  |  |  |

| `to_map` | function | to_map/1 |  |  |  |  |

| `verdicts` | function | verdicts/0 |  |  |  |  |

| `AshGraphLaw.Mutation.Verdict` | struct | defstruct mutation_id, target, verdict, code, detail, mutant_calls, applied, restored, baseline, mutant, killers: [], killer_files: [], missing_killers: [], killed_by: [] |  |  |  |  |

| t | type | @type t :: %__MODULE__{ mutation_id: String.t(), target: String.t(), verdict: verdict(), code: atom() | nil, detail: String.t() | nil, mutant_calls: non_neg_integer() | nil, applied: map() | nil, restored: map() | nil, baseline: map() | nil, mutant: map() | nil, killers: [String.t()], killer_files: [String.t()], missing_killers: [String.t()], killed_by: [String.t()] } |  |  |  |  |

| `verdict` | type | @type verdict :: :mutant_killed | :mutant_survived | :blocked | :unknown |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
