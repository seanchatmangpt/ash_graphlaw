# ash_graphlaw reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### AshGraphLaw.Capability.Registry

| `abi_version` | function | abi_version/0 |  |  |  |  |

| `dialects` | function | dialects/0 |  |  |  |  |

| `digest` | function | digest/0 |  |  |  |  |

| `engines` | function | engines/0 |  |  |  |  |

| `graphlaw_version` | function | graphlaw_version/0 |  |  |  |  |

| `law_steps` | function | law_steps/0 |  |  |  |  |

| `lease_ceilings` | function | lease_ceilings/0 |  |  |  |  |

| `lease_reasons` | function | lease_reasons/0 |  |  |  |  |

| `limits` | function | limits/0 |  |  |  |  |

| `module_for` | function | module_for/1 |  |  |  |  |

| `names` | function | names/0 |  |  |  |  |

| op | function | op/1 |  |  |  |  |

| `ops` | function | ops/0 |  |  |  |  |

| `other_dialects` | function | other_dialects/0 |  |  |  |  |

| `policy_refusal_kinds` | function | policy_refusal_kinds/0 |  |  |  |  |

| `rdf_dialects` | function | rdf_dialects/0 |  |  |  |  |

| `receipt_reasons` | function | receipt_reasons/0 |  |  |  |  |

| `refusal_codes` | function | refusal_codes/0 |  |  |  |  |

| `refusal_kinds` | function | refusal_kinds/0 |  |  |  |  |

| `regimes` | function | regimes/0 |  |  |  |  |

| `schema` | function | schema/0 |  |  |  |  |

| `surface_digest` | function | surface_digest/0 |  |  |  |  |

| `vocabulary` | function | vocabulary/1 |  |  |  |  |

| `dialect` | type | @type dialect :: %{ name: String.t(), order: pos_integer(), aliases: [String.t()], response_name: String.t(), media_type: String.t() | nil, kind: String.t() } |  |  |  |  |

| `field` | type | @type field :: %{ name: String.t(), order: pos_integer(), type: String.t(), required: boolean(), nullable: boolean(), doc: String.t(), enum: [String.t()] | nil, default: String.t() | integer() | boolean() | nil } |  |  |  |  |

| `law_step` | type | @type law_step :: %{ name: String.t(), order: pos_integer(), ceiling: String.t() | nil, fields: [field()] } |  |  |  |  |

| op | type | @type op :: %{ name: String.t(), order: pos_integer(), summary: String.t(), request: [field()], responses: [variant()], refusal_kinds: [String.t()], refusal_codes: [String.t()] } |  |  |  |  |

| `refusal_code` | type | @type refusal_code :: %{ code: String.t(), order: pos_integer(), kind: String.t() | nil, fields: [field()] } |  |  |  |  |

| `variant` | type | @type variant :: %{tag: String.t() | nil, tag_field: String.t() | nil, fields: [field()]} |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `abi_version` | function | abi_version/0 |  |  |  |  |

| `dialects` | function | dialects/0 |  |  |  |  |

| `digest` | function | digest/0 |  |  |  |  |

| `engines` | function | engines/0 |  |  |  |  |

| `graphlaw_version` | function | graphlaw_version/0 |  |  |  |  |

| `law_steps` | function | law_steps/0 |  |  |  |  |

| `lease_ceilings` | function | lease_ceilings/0 |  |  |  |  |

| `lease_reasons` | function | lease_reasons/0 |  |  |  |  |

| `limits` | function | limits/0 |  |  |  |  |

| `module_for` | function | module_for/1 |  |  |  |  |

| `names` | function | names/0 |  |  |  |  |

| op | function | op/1 |  |  |  |  |

| `ops` | function | ops/0 |  |  |  |  |

| `other_dialects` | function | other_dialects/0 |  |  |  |  |

| `policy_refusal_kinds` | function | policy_refusal_kinds/0 |  |  |  |  |

| `rdf_dialects` | function | rdf_dialects/0 |  |  |  |  |

| `receipt_reasons` | function | receipt_reasons/0 |  |  |  |  |

| `refusal_codes` | function | refusal_codes/0 |  |  |  |  |

| `refusal_kinds` | function | refusal_kinds/0 |  |  |  |  |

| `regimes` | function | regimes/0 |  |  |  |  |

| `schema` | function | schema/0 |  |  |  |  |

| `surface_digest` | function | surface_digest/0 |  |  |  |  |

| `vocabulary` | function | vocabulary/1 |  |  |  |  |

| `dialect` | type | @type dialect :: %{ name: String.t(), order: pos_integer(), aliases: [String.t()], response_name: String.t(), media_type: String.t() | nil, kind: String.t() } |  |  |  |  |

| `field` | type | @type field :: %{ name: String.t(), order: pos_integer(), type: String.t(), required: boolean(), nullable: boolean(), doc: String.t(), enum: [String.t()] | nil, default: String.t() | integer() | boolean() | nil } |  |  |  |  |

| `law_step` | type | @type law_step :: %{ name: String.t(), order: pos_integer(), ceiling: String.t() | nil, fields: [field()] } |  |  |  |  |

| op | type | @type op :: %{ name: String.t(), order: pos_integer(), summary: String.t(), request: [field()], responses: [variant()], refusal_kinds: [String.t()], refusal_codes: [String.t()] } |  |  |  |  |

| `refusal_code` | type | @type refusal_code :: %{ code: String.t(), order: pos_integer(), kind: String.t() | nil, fields: [field()] } |  |  |  |  |

| `variant` | type | @type variant :: %{tag: String.t() | nil, tag_field: String.t() | nil, fields: [field()]} |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
